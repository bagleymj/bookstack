require "rails_helper"

RSpec.describe "Books", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }

  before { sign_in user }

  describe "POST /books/:id/update_progress" do
    context "when advancing forward" do
      let(:book) { create(:book, :reading, user: user, current_page: 50, last_page: 300) }

      it "creates an untracked reading session" do
        expect {
          post update_progress_book_path(book), params: { page: 80 }
        }.to change(ReadingSession, :count).by(1)

        session = ReadingSession.last
        expect(session.start_page).to eq(50)
        expect(session.end_page).to eq(80)
        expect(session.untracked?).to be true
        expect(session.completed?).to be true
      end

      it "sets estimated duration on the untracked session" do
        post update_progress_book_path(book), params: { page: 80 }

        session = ReadingSession.last
        expect(session.estimated_duration_seconds).to be_present
      end

      it "updates book current_page" do
        post update_progress_book_path(book), params: { page: 80 }

        expect(book.reload.current_page).to eq(80)
      end

      it "updates daily quota actual_pages" do
        goal = create(:reading_goal, user: user, book: book, status: :active)
        quota = goal.today_quota

        post update_progress_book_path(book), params: { page: 80 }

        expect(quota.reload.actual_pages).to eq(30)
      end

      it "does not recalculate user reading stats" do
        expect(ReadingStatsCalculator).not_to receive(:new)

        post update_progress_book_path(book), params: { page: 80 }
      end

      it "transitions unread book to reading" do
        unread_book = create(:book, :unread, user: user, current_page: 1, last_page: 300)

        post update_progress_book_path(unread_book), params: { page: 20 }

        expect(unread_book.reload.status).to eq("reading")
      end
    end

    context "when page is same or lower" do
      let(:book) { create(:book, :reading, user: user, current_page: 50, last_page: 300) }

      it "does not create a reading session for same page" do
        expect {
          post update_progress_book_path(book), params: { page: 50 }
        }.not_to change(ReadingSession, :count)
      end

      it "does not create a reading session for lower page" do
        expect {
          post update_progress_book_path(book), params: { page: 30 }
        }.not_to change(ReadingSession, :count)
      end
    end
  end

  describe "PATCH /books/:id (page range change)" do
    let(:user) do
      create(:user,
        onboarding_completed_at: Time.current,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: Date.current.beginning_of_year,
        default_reading_speed_wpm: 250,
        max_concurrent_books: 3,
        weekend_mode: :same,
        weekday_reading_minutes: 60,
        weekend_reading_minutes: 60)
    end

    it "reschedules uncommitted books when page range changes" do
      sign_in user
      # Start with a queued book — scheduler will place it
      book = create(:book, user: user, first_page: 1, last_page: 400)
      goal = create(:reading_goal,
        user: user, book: book, status: :queued,
        started_on: nil, target_completion_date: nil,
        auto_scheduled: true, position: 1)

      # Initial schedule places the book
      ReadingListScheduler.new(user).schedule!
      goal.reload
      initial_total = goal.daily_quotas.sum(:target_pages)
      expect(initial_total).to eq(book.remaining_pages)

      # Shorten the book — reschedule_if_on_pipeline! triggers
      patch book_path(book), params: { book: { last_page: 300 } }

      expect(book.reload.total_pages).to eq(300)
      goal.reload
      new_total = DailyQuota.where(reading_goal_id: goal.id).sum(:target_pages)
      expect(new_total).to eq(book.remaining_pages)
    end
  end
end
