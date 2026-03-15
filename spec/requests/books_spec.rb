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

    it "rebuilds schedule for a future book even when user has read other books this week" do
      # Book the user is actively reading this week
      current_book = create(:book, :reading, user: user, last_page: 200, current_page: 50)
      current_goal = create(:reading_goal,
        user: user, book: current_book, status: :active,
        started_on: Date.current.beginning_of_week(:monday),
        target_completion_date: Date.current.end_of_week(:sunday),
        auto_scheduled: true, position: 1)
      ProfileAwareQuotaCalculator.new(current_goal, user).generate_quotas!
      create(:reading_session, :completed, user: user, book: current_book,
        started_at: 2.days.ago, ended_at: 2.days.ago + 1.hour,
        start_page: 50, end_page: 70)

      # Future book — not read this week
      future_book = create(:book, user: user, first_page: 1, last_page: 400)
      future_goal = create(:reading_goal,
        user: user, book: future_book, status: :active,
        started_on: Date.current.next_week(:monday),
        target_completion_date: 28.days.from_now.to_date,
        auto_scheduled: true, position: 2)
      ProfileAwareQuotaCalculator.new(future_goal, user).generate_quotas!

      old_end_date = future_goal.target_completion_date

      # Shorten the future book by 100 pages
      patch book_path(future_book), params: { book: { last_page: 300 } }

      future_goal.reload
      new_total = future_goal.daily_quotas.sum(:target_pages)

      expect(future_book.reload.total_pages).to eq(300)
      # Quotas rebuilt to match new remaining pages
      expect(new_total).to eq(future_book.remaining_pages)
      # This week's book stays locked
      expect(current_goal.reload.status).to eq("active")
    end
  end
end
