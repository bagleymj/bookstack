require "rails_helper"

RSpec.describe DailyQuota, type: :model do
  let(:user) { create(:user, weekend_mode: :same) }
  let(:book) { create(:book, user: user, first_page: 1, last_page: 200, current_page: 1) }
  let(:goal) do
    g = create(:reading_goal, user: user, book: book, status: :active,
               started_on: Date.current, target_completion_date: 10.days.from_now.to_date)
    g.daily_quotas.destroy_all
    (Date.current..10.days.from_now.to_date).each do |date|
      g.daily_quotas.create!(date: date, target_pages: 18, actual_pages: 0, status: :pending)
    end
    g
  end

  before { goal }

  describe "validations" do
    it "requires a date" do
      quota = build(:daily_quota, reading_goal: goal, date: nil)
      expect(quota).not_to be_valid
    end

    it "requires target_pages greater than 0" do
      quota = build(:daily_quota, reading_goal: goal, target_pages: 0)
      expect(quota).not_to be_valid
    end

    it "requires actual_pages >= 0" do
      quota = build(:daily_quota, reading_goal: goal, actual_pages: -1)
      expect(quota).not_to be_valid
    end
  end

  describe "#pages_remaining" do
    it "returns target_pages minus actual_pages" do
      quota = build(:daily_quota, target_pages: 20, actual_pages: 5)
      expect(quota.pages_remaining).to eq(15)
    end

    it "returns 0 when actual exceeds target" do
      quota = build(:daily_quota, target_pages: 10, actual_pages: 15)
      expect(quota.pages_remaining).to eq(0)
    end

    it "returns full target when nothing read" do
      quota = build(:daily_quota, target_pages: 20, actual_pages: 0)
      expect(quota.pages_remaining).to eq(20)
    end
  end

  describe "#percentage_complete" do
    it "returns 0 when nothing read" do
      quota = goal.daily_quotas.first
      expect(quota.percentage_complete).to eq(0)
    end

    it "returns percentage based on actual/target" do
      quota = goal.daily_quotas.first
      quota.update!(actual_pages: 9)
      expect(quota.percentage_complete).to eq(50)
    end

    it "caps at 100" do
      quota = goal.daily_quotas.first
      quota.update!(actual_pages: 25)
      expect(quota.percentage_complete).to eq(100)
    end

    it "returns 100 when effectively complete" do
      quota = goal.daily_quotas.first
      quota.update!(status: :completed)
      expect(quota.percentage_complete).to eq(100)
    end
  end

  describe "#effectively_complete?" do
    it "returns true when status is completed" do
      quota = goal.daily_quotas.first
      quota.update!(status: :completed)
      expect(quota.effectively_complete?).to be true
    end

    it "returns true when book has reached target page" do
      # The book's current_page is past the quota's target_page_number
      quota = goal.daily_quotas.first
      book.update!(current_page: book.last_page)
      expect(quota.effectively_complete?).to be true
    end

    it "returns false when quota is pending and book not at target" do
      quota = goal.daily_quotas.first
      expect(quota.effectively_complete?).to be false
    end
  end

  describe "#record_pages!" do
    it "adds pages to actual_pages" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.record_pages!(5)
      expect(quota.reload.actual_pages).to eq(5)
    end

    it "accumulates across multiple calls" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.record_pages!(5)
      quota.record_pages!(8)
      expect(quota.reload.actual_pages).to eq(13)
    end

    it "marks as completed when target is met" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.record_pages!(18)
      expect(quota.reload.status).to eq("completed")
    end

    it "marks as completed when actual exceeds target" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.record_pages!(25)
      expect(quota.reload.status).to eq("completed")
    end

    it "stays pending when target not yet met" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.record_pages!(5)
      expect(quota.reload.status).to eq("pending")
    end
  end

  describe "#mark_missed!" do
    it "marks incomplete past quotas as missed" do
      yesterday = goal.daily_quotas.find_by(date: Date.current)
      # Simulate a past quota by updating the date
      yesterday.update_columns(date: Date.yesterday)

      yesterday.mark_missed!
      expect(yesterday.reload.status).to eq("missed")
    end

    it "does not mark completed quotas as missed" do
      yesterday = goal.daily_quotas.first
      yesterday.update_columns(date: Date.yesterday, status: DailyQuota.statuses[:completed])

      yesterday.mark_missed!
      expect(yesterday.reload.status).to eq("completed")
    end

    it "does not mark future quotas as missed" do
      future_quota = goal.daily_quotas.find_by(date: Date.current)
      future_quota.mark_missed!
      expect(future_quota.reload.status).not_to eq("missed")
    end
  end

  describe "#estimated_minutes_remaining" do
    it "returns 0 when effectively complete" do
      quota = goal.daily_quotas.first
      quota.update!(status: :completed)
      expect(quota.estimated_minutes_remaining).to eq(0)
    end

    it "returns positive minutes when pages remain" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      expect(quota.estimated_minutes_remaining).to be > 0
    end

    it "returns 0 when no pages remain" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.update!(actual_pages: 18)
      # Still pending status, but effectively_complete checks book position
      # For this test, the quota may not be "effectively complete" unless book is at target
      # so estimated_minutes_remaining depends on pages_remaining
      expect(quota.estimated_minutes_remaining).to eq(0)
    end
  end

  describe "#target_page_number" do
    it "returns cumulative target page through this date" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      target = quota.target_page_number

      # Should be goal_start_page + cumulative target pages through today
      expect(target).to be > book.first_page
      expect(target).to be <= book.last_page
    end

    it "increases for later dates" do
      quotas = goal.daily_quotas.order(:date).to_a
      targets = quotas.map(&:target_page_number)

      # Each day's target should be >= the previous
      targets.each_cons(2) do |earlier, later|
        expect(later).to be >= earlier
      end
    end
  end

  describe "scopes" do
    it ".for_date returns quotas for a specific date" do
      expect(DailyQuota.for_date(Date.current).count).to be >= 1
    end

    it ".today returns today's quotas" do
      expect(DailyQuota.today.count).to be >= 1
    end

    it ".incomplete excludes completed quotas" do
      quota = goal.daily_quotas.first
      quota.update!(status: :completed)
      expect(DailyQuota.incomplete).not_to include(quota)
    end

    it ".past returns only past quotas" do
      expect(DailyQuota.past.where("date >= ?", Date.current).count).to eq(0)
    end

    it ".future returns only future quotas" do
      expect(DailyQuota.future.where("date <= ?", Date.current).count).to eq(0)
    end
  end

  describe "#book and #user delegations" do
    it "returns the reading goal's book" do
      quota = goal.daily_quotas.first
      expect(quota.book).to eq(book)
    end

    it "returns the reading goal's user" do
      quota = goal.daily_quotas.first
      expect(quota.user).to eq(user)
    end
  end
end
