require "rails_helper"

RSpec.describe ReadingSession, type: :model do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }
  let(:book) { create(:book, :reading, user: user, first_page: 1, last_page: 300, current_page: 50) }

  describe "validations" do
    describe "#end_page_greater_than_start_page" do
      it "is invalid when end_page is less than start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 30)
        expect(session).not_to be_valid
        expect(session.errors[:end_page]).to include("must be greater than or equal to start page")
      end

      it "is valid when end_page equals start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 50)
        expect(session).to be_valid
      end

      it "is valid when end_page is greater than start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 75)
        expect(session).to be_valid
      end

      it "skips validation when end_page is nil" do
        session = build(:reading_session, :in_progress, user: user, book: book, start_page: 50)
        expect(session).to be_valid
      end
    end

    it "requires started_at" do
      session = build(:reading_session, user: user, book: book, started_at: nil)
      expect(session).not_to be_valid
    end

    it "requires start_page >= 0" do
      session = build(:reading_session, user: user, book: book, start_page: -1)
      expect(session).not_to be_valid
    end

    describe "#only_one_in_progress_per_user" do
      it "prevents creating a second in-progress session" do
        create(:reading_session, :in_progress, user: user, book: book)
        other_book = create(:book, :reading, user: user)
        session = build(:reading_session, :in_progress, user: user, book: other_book)
        expect(session).not_to be_valid
        expect(session.errors[:base]).to include("You already have an active reading session")
      end

      it "allows a new in-progress session after the first is completed" do
        first = create(:reading_session, :in_progress, user: user, book: book)
        first.update!(ended_at: Time.current, end_page: 75)

        other_book = create(:book, :reading, user: user)
        session = build(:reading_session, :in_progress, user: user, book: other_book)
        expect(session).to be_valid
      end
    end
  end

  describe "scopes" do
    before do
      create(:reading_session, :completed, user: user, book: book)
      create(:reading_session, :in_progress, user: user, book: book)
    end

    it ".completed returns only completed sessions" do
      expect(ReadingSession.completed.all? { |s| s.ended_at.present? }).to be true
    end

    it ".in_progress returns only in-progress sessions" do
      expect(ReadingSession.in_progress.all? { |s| s.ended_at.nil? }).to be true
    end

    it ".recent orders by started_at desc" do
      sessions = ReadingSession.recent
      started_ats = sessions.pluck(:started_at)
      expect(started_ats).to eq(started_ats.sort.reverse)
    end

    it ".for_date returns sessions for a specific date" do
      today_sessions = ReadingSession.for_date(Date.current)
      expect(today_sessions.count).to be >= 1
    end
  end

  describe "#completed?" do
    it "returns true when ended_at and end_page are present" do
      session = build(:reading_session, :completed, user: user, book: book)
      expect(session.completed?).to be true
    end

    it "returns false when ended_at is nil" do
      session = build(:reading_session, :in_progress, user: user, book: book)
      expect(session.completed?).to be false
    end

    it "returns false when end_page is nil" do
      session = build(:reading_session, user: user, book: book, ended_at: Time.current, end_page: nil)
      expect(session.completed?).to be false
    end
  end

  describe "#in_progress?" do
    it "returns true when ended_at is nil" do
      session = build(:reading_session, :in_progress, user: user, book: book)
      expect(session.in_progress?).to be true
    end

    it "returns false when ended_at is present" do
      session = build(:reading_session, :completed, user: user, book: book)
      expect(session.in_progress?).to be false
    end
  end

  describe "#complete!" do
    let(:session) { create(:reading_session, :in_progress, user: user, book: book, start_page: 50) }

    it "sets ended_at and end_page" do
      session.complete!(75)
      expect(session.ended_at).to be_present
      expect(session.end_page).to eq(75)
    end

    it "updates book progress" do
      session.complete!(75)
      expect(book.reload.current_page).to eq(75)
    end

    it "calculates metrics on save" do
      session.complete!(75)
      expect(session.pages_read).to eq(25)
      expect(session.duration_seconds).to be > 0
    end
  end

  describe "#calculated_pages_read" do
    it "returns end_page minus start_page" do
      session = build(:reading_session, start_page: 10, end_page: 30)
      expect(session.calculated_pages_read).to eq(20)
    end

    it "returns 0 when end_page equals start_page" do
      session = build(:reading_session, start_page: 10, end_page: 10)
      expect(session.calculated_pages_read).to eq(0)
    end

    it "returns 0 when end_page is nil" do
      session = build(:reading_session, start_page: 10, end_page: nil)
      expect(session.calculated_pages_read).to eq(0)
    end
  end

  describe "#calculated_wpm" do
    it "calculates words per minute for completed sessions" do
      session = create(:reading_session, :completed, user: user, book: book,
                       start_page: 50, end_page: 60, duration_seconds: 600)
      # 10 pages * 250 words = 2500 words / 10 minutes = 250 WPM
      expect(session.calculated_wpm).to eq(250.0)
    end

    it "returns nil for in-progress sessions" do
      session = build(:reading_session, :in_progress, user: user, book: book)
      expect(session.calculated_wpm).to be_nil
    end

    it "returns nil when duration is zero" do
      session = build(:reading_session, :completed, user: user, book: book,
                      start_page: 50, end_page: 60, duration_seconds: 0)
      expect(session.calculated_wpm).to be_nil
    end
  end

  describe "#effective_duration_seconds" do
    it "returns duration_seconds for tracked sessions" do
      session = build(:reading_session, :completed, untracked: false, duration_seconds: 1800)
      expect(session.effective_duration_seconds).to eq(1800)
    end

    it "returns estimated_duration_seconds for untracked sessions" do
      session = build(:reading_session, :completed, untracked: true,
                      duration_seconds: 1800, estimated_duration_seconds: 1200)
      expect(session.effective_duration_seconds).to eq(1200)
    end
  end

  describe "#formatted_duration" do
    it "formats seconds only" do
      session = build(:reading_session, :completed, duration_seconds: 30, untracked: false)
      expect(session.formatted_duration).to eq("30 sec")
    end

    it "formats minutes" do
      session = build(:reading_session, :completed, duration_seconds: 300, untracked: false)
      expect(session.formatted_duration).to eq("5 min")
    end

    it "formats hours and minutes" do
      session = build(:reading_session, :completed, duration_seconds: 5400, untracked: false)
      expect(session.formatted_duration).to eq("1h 30m")
    end

    it "returns 0 min when nil" do
      session = build(:reading_session, :completed, duration_seconds: nil, untracked: false)
      expect(session.formatted_duration).to eq("0 min")
    end
  end

  describe "callbacks" do
    it "calculates metrics before save when completed" do
      session = create(:reading_session, :in_progress, user: user, book: book, start_page: 50)
      session.update!(ended_at: Time.current, end_page: 75)
      expect(session.pages_read).to eq(25)
      expect(session.duration_seconds).to be > 0
    end

    it "does not set WPM for untracked sessions" do
      session = create(:reading_session, user: user, book: book,
                       start_page: 50, end_page: 60, started_at: 10.minutes.ago,
                       ended_at: Time.current, untracked: true)
      expect(session.words_per_minute).to be_nil
    end

    it "calculates estimated_duration for untracked sessions" do
      session = create(:reading_session, user: user, book: book,
                       start_page: 50, end_page: 60, started_at: 10.minutes.ago,
                       ended_at: Time.current, untracked: true)
      expect(session.estimated_duration_seconds).to be_present
    end

    it "updates user reading stats after save for tracked sessions" do
      expect {
        create(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 60)
      }.to change { user.user_reading_stats.reload.total_sessions }
    end

    it "does not update user reading stats for untracked sessions" do
      original = user.user_reading_stats.total_sessions
      create(:reading_session, user: user, book: book,
             start_page: 50, end_page: 60, started_at: 10.minutes.ago,
             ended_at: Time.current, untracked: true)
      expect(user.user_reading_stats.reload.total_sessions).to eq(original)
    end
  end

  describe "#duration" do
    it "returns difference between ended_at and started_at" do
      session = build(:reading_session, started_at: 1.hour.ago, ended_at: Time.current)
      expect(session.duration).to be_within(5).of(3600)
    end

    it "returns nil when ended_at is nil" do
      session = build(:reading_session, :in_progress)
      expect(session.duration).to be_nil
    end
  end
end
