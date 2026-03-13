require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires a positive default_words_per_page" do
      user = build(:user, default_words_per_page: 0)
      expect(user).not_to be_valid
      expect(user.errors[:default_words_per_page]).to be_present
    end

    it "requires a positive default_reading_speed_wpm" do
      user = build(:user, default_reading_speed_wpm: 0)
      expect(user).not_to be_valid
    end

    it "requires a positive max_concurrent_books" do
      user = build(:user, max_concurrent_books: 0)
      expect(user).not_to be_valid
    end

    it "allows zero weekday_reading_minutes" do
      user = build(:user, weekday_reading_minutes: 0)
      expect(user).to be_valid
    end

    it "rejects negative weekday_reading_minutes" do
      user = build(:user, weekday_reading_minutes: -1)
      expect(user).not_to be_valid
    end

    it "validates reading_pace_type inclusion" do
      user = build(:user, reading_pace_type: "pages_per_day")
      expect(user).not_to be_valid
    end

    it "allows nil reading_pace_type" do
      user = build(:user, reading_pace_type: nil)
      expect(user).to be_valid
    end

    it "requires positive integer reading_pace_value when set" do
      user = build(:user, reading_pace_value: 0)
      expect(user).not_to be_valid
    end

    it "requires integer concurrency_limit when set" do
      user = build(:user, concurrency_limit: 2)
      expect(user).to be_valid
    end
  end

  describe "associations" do
    let(:user) { create(:user) }

    it "creates reading stats on create" do
      expect(user.user_reading_stats).to be_present
    end

    it "destroys dependent books" do
      create(:book, user: user)
      expect { user.destroy }.to change(Book, :count).by(-1)
    end

    it "destroys dependent reading sessions" do
      book = create(:book, user: user)
      create(:reading_session, :completed, user: user, book: book)
      expect { user.destroy }.to change(ReadingSession, :count).by(-1)
    end

    it "destroys dependent reading goals" do
      book = create(:book, user: user)
      create(:reading_goal, user: user, book: book)
      expect { user.destroy }.to change(ReadingGoal, :count).by(-1)
    end
  end

  describe "#effective_reading_speed" do
    let(:user) { create(:user, default_reading_speed_wpm: 200) }

    it "returns user_reading_stats average_wpm when available" do
      user.user_reading_stats.update!(average_wpm: 275.0)
      expect(user.effective_reading_speed).to eq(275.0)
    end

    it "falls back to default_reading_speed_wpm when stats use default" do
      expect(user.effective_reading_speed).to be > 0
    end
  end

  describe "#includes_weekends?" do
    it "returns true when weekend_mode is same" do
      user = build(:user, weekend_mode: :same)
      expect(user.includes_weekends?).to be true
    end

    it "returns false when weekend_mode is skip" do
      user = build(:user, weekend_mode: :skip)
      expect(user.includes_weekends?).to be false
    end
  end

  describe "#onboarding_completed?" do
    it "returns false when onboarding_completed_at is nil" do
      user = build(:user, onboarding_completed_at: nil)
      expect(user.onboarding_completed?).to be false
    end

    it "returns true when onboarding_completed_at is set" do
      user = build(:user, onboarding_completed_at: Time.current)
      expect(user.onboarding_completed?).to be true
    end
  end

  describe "#reading_pace_progress" do
    it "returns nil when pace is not configured" do
      user = create(:user, reading_pace_type: nil)
      expect(user.reading_pace_progress).to be_nil
    end

    it "returns progress hash for books_per_year pace" do
      user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: Date.current.beginning_of_year)

      progress = user.reading_pace_progress
      expect(progress).to be_a(Hash)
      expect(progress[:target_rate]).to eq(50)
      expect(progress[:unit]).to eq("books/year")
      expect(progress[:current]).to eq(0)
    end

    it "counts completed books since pace start" do
      user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: 30.days.ago.to_date)

      create(:book, :completed, user: user, completed_at: 10.days.ago)
      progress = user.reading_pace_progress
      expect(progress[:current]).to eq(1)
    end

    it "does not count books completed before pace start" do
      user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: 10.days.ago.to_date)

      create(:book, :completed, user: user, completed_at: 30.days.ago)
      progress = user.reading_pace_progress
      expect(progress[:current]).to eq(0)
    end
  end

  describe "#derive_daily_minutes_from_pace" do
    it "returns nil when pace is not configured" do
      user = create(:user, reading_pace_type: nil)
      expect(user.derive_daily_minutes_from_pace).to be_nil
    end

    it "calculates daily minutes for books_per_year" do
      user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 52,
        default_reading_speed_wpm: 250)

      minutes = user.derive_daily_minutes_from_pace
      expect(minutes).to be > 0
      expect(minutes).to be_a(Integer)
    end

    it "calculates daily minutes for books_per_month" do
      user = create(:user,
        reading_pace_type: "books_per_month",
        reading_pace_value: 4,
        default_reading_speed_wpm: 250)

      minutes = user.derive_daily_minutes_from_pace
      expect(minutes).to be > 0
    end

    it "calculates daily minutes for books_per_week" do
      user = create(:user,
        reading_pace_type: "books_per_week",
        reading_pace_value: 1,
        default_reading_speed_wpm: 250)

      minutes = user.derive_daily_minutes_from_pace
      expect(minutes).to be > 0
    end
  end

  describe "#effective_concurrency_limit" do
    it "returns concurrency_limit when set" do
      user = build(:user, concurrency_limit: 5, max_concurrent_books: 3)
      expect(user.effective_concurrency_limit).to eq(5)
    end

    it "falls back to max_concurrent_books" do
      user = build(:user, concurrency_limit: nil, max_concurrent_books: 3)
      expect(user.effective_concurrency_limit).to eq(3)
    end
  end

  describe "#reading_pace_label" do
    it "returns nil when pace_type is nil" do
      user = build(:user, reading_pace_type: nil)
      expect(user.reading_pace_label).to be_nil
    end

    it "returns correct label for each pace type" do
      expect(build(:user, reading_pace_type: "books_per_year").reading_pace_label).to eq("books/year")
      expect(build(:user, reading_pace_type: "books_per_month").reading_pace_label).to eq("books/month")
      expect(build(:user, reading_pace_type: "books_per_week").reading_pace_label).to eq("books/week")
    end
  end

  describe "#weekend_target" do
    it "returns 0 when weekend_mode is skip" do
      user = build(:user, weekend_mode: :skip, weekday_reading_minutes: 60)
      expect(user.weekend_target).to eq(0)
    end

    it "returns weekday_reading_minutes when weekend_mode is same" do
      user = build(:user, weekend_mode: :same, weekday_reading_minutes: 60)
      expect(user.weekend_target).to eq(60)
    end
  end
end
