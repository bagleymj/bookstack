require "rails_helper"

RSpec.describe ReadingGoal, type: :model do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      weekend_mode: :same)
  end
  let(:book) { create(:book, user: user, last_page: 200, current_page: 1) }

  describe "validations" do
    it "requires target_completion_date for non-queued goals" do
      goal = build(:reading_goal, user: user, book: book, status: :active, target_completion_date: nil)
      expect(goal).not_to be_valid
    end

    it "does not require target_completion_date for queued goals" do
      goal = build(:reading_goal, user: user, book: book, status: :queued,
                   target_completion_date: nil, started_on: nil)
      expect(goal).to be_valid
    end

    it "requires target_completion_date after started_on" do
      goal = build(:reading_goal, user: user, book: book,
                   started_on: Date.current, target_completion_date: Date.yesterday)
      expect(goal).not_to be_valid
    end

    it "prevents duplicate active goals for the same book" do
      create(:reading_goal, user: user, book: book, status: :active)
      duplicate = build(:reading_goal, user: user, book: book, status: :active)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:book]).to include("already has an active or queued reading goal")
    end

    it "prevents duplicate queued goals for the same book" do
      create(:reading_goal, user: user, book: book, status: :queued,
             started_on: nil, target_completion_date: nil)
      duplicate = build(:reading_goal, user: user, book: book, status: :queued,
                        started_on: nil, target_completion_date: nil)
      expect(duplicate).not_to be_valid
    end

    it "allows a new goal after previous is completed" do
      create(:reading_goal, user: user, book: book, status: :completed)
      new_goal = build(:reading_goal, user: user, book: book, status: :active)
      expect(new_goal).to be_valid
    end
  end

  describe "#mark_completed!" do
    let(:goal) do
      create(:reading_goal, user: user, book: book, status: :active,
             started_on: 1.week.ago.to_date, target_completion_date: Date.current,
             auto_scheduled: true, position: 1)
    end

    it "sets status to completed" do
      goal.mark_completed!
      expect(goal.reload.status).to eq("completed")
    end

    it "does not call ReadingListScheduler#schedule!" do
      expect(ReadingListScheduler).not_to receive(:new)
      goal.mark_completed!
    end
  end

  describe "#mark_abandoned!" do
    let(:goal) do
      create(:reading_goal, user: user, book: book, status: :active,
             started_on: 1.week.ago.to_date, target_completion_date: Date.current,
             auto_scheduled: true, position: 1)
    end

    it "sets status to abandoned" do
      goal.mark_abandoned!
      expect(goal.reload.status).to eq("abandoned")
    end

    it "does not call ReadingListScheduler#schedule!" do
      expect(ReadingListScheduler).not_to receive(:new)
      goal.mark_abandoned!
    end
  end

  describe "#reading_days_remaining" do
    it "returns 0 for queued goals" do
      goal = build(:reading_goal, user: user, book: book, status: :queued,
                   started_on: nil, target_completion_date: nil)
      expect(goal.reading_days_remaining).to eq(0)
    end

    it "returns 0 when target_completion_date is past" do
      goal = build(:reading_goal, user: user, book: book,
                   started_on: 2.weeks.ago.to_date,
                   target_completion_date: Date.yesterday)
      expect(goal.reading_days_remaining).to eq(0)
    end

    it "counts all days when weekends included" do
      goal = build(:reading_goal, user: user, book: book,
                   started_on: Date.current,
                   target_completion_date: 6.days.from_now.to_date)
      expect(goal.reading_days_remaining).to eq(7) # today + 6 days
    end

    it "excludes weekends when user skips weekends" do
      user.update!(weekend_mode: :skip)
      goal = build(:reading_goal, user: user, book: book,
                   started_on: Date.current,
                   target_completion_date: 13.days.from_now.to_date)
      # 14 days, minus 4 weekend days = 10
      remaining = goal.reading_days_remaining
      expect(remaining).to be < 14
      expect(remaining).to be > 0
    end
  end

  describe "#pages_per_day" do
    it "returns 0 when no reading days remaining" do
      goal = build(:reading_goal, user: user, book: book,
                   started_on: 2.weeks.ago.to_date,
                   target_completion_date: Date.yesterday)
      expect(goal.pages_per_day).to eq(0)
    end

    it "calculates pages per day based on remaining pages and days" do
      goal = create(:reading_goal, user: user, book: book,
                    started_on: Date.current,
                    target_completion_date: 9.days.from_now.to_date)
      # 199 remaining pages / 10 days = 20 pages/day (ceiling)
      expect(goal.pages_per_day).to eq((199.0 / 10).ceil)
    end
  end

  describe "#tracking_status" do
    let(:goal) do
      g = create(:reading_goal, user: user, book: book, status: :active,
                 started_on: 1.week.ago.to_date, target_completion_date: 1.week.from_now.to_date)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 25, actual_pages: 0, status: :pending)
      end
      g
    end

    it "returns :caught_up for completed goals" do
      goal.update!(status: :completed)
      expect(goal.tracking_status).to eq(:caught_up)
    end

    it "returns :behind for abandoned goals" do
      goal.update!(status: :abandoned)
      expect(goal.tracking_status).to eq(:behind)
    end

    it "returns nil for not-started goals" do
      goal.update!(started_on: Date.tomorrow)
      expect(goal.tracking_status).to be_nil
    end

    it "returns :reading_due when today's quota is pending" do
      expect(goal.tracking_status).to eq(:reading_due)
    end

    it "returns :caught_up when today's quota is complete" do
      quota = goal.daily_quotas.find_by(date: Date.current)
      quota.update!(actual_pages: 25, status: :completed)
      expect(goal.tracking_status).to eq(:caught_up)
    end

    it "returns :behind when today's quota pending and past quotas pending" do
      # Create a past pending quota
      goal.daily_quotas.create!(date: Date.yesterday, target_pages: 25,
                                actual_pages: 0, status: :pending)
      expect(goal.tracking_status).to eq(:behind)
    end
  end

  describe "#today_quota" do
    it "returns today's non-missed quota" do
      goal = create(:reading_goal, user: user, book: book,
                    started_on: Date.current, target_completion_date: 7.days.from_now.to_date)
      expect(goal.today_quota).to be_present
      expect(goal.today_quota.date).to eq(Date.current)
    end

    it "returns nil when today's quota is missed" do
      goal = create(:reading_goal, user: user, book: book,
                    started_on: Date.current, target_completion_date: 7.days.from_now.to_date)
      goal.today_quota.update!(status: :missed)
      expect(goal.today_quota).to be_nil
    end
  end

  describe "#yesterday_discrepancy" do
    let(:goal) do
      g = create(:reading_goal, user: user, book: book, status: :active,
                 started_on: 3.days.ago.to_date, target_completion_date: 7.days.from_now.to_date)
      g.daily_quotas.destroy_all
      (3.days.ago.to_date..7.days.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end
      g
    end

    it "returns nil when yesterday's quota doesn't exist" do
      goal.daily_quotas.find_by(date: Date.yesterday)&.destroy
      expect(goal.yesterday_discrepancy).to be_nil
    end

    it "returns :behind when actual < target" do
      quota = goal.daily_quotas.find_by(date: Date.yesterday)
      quota.update!(actual_pages: 10)
      disc = goal.yesterday_discrepancy
      expect(disc[:type]).to eq(:behind)
      expect(disc[:pages]).to eq(10)
    end

    it "returns :ahead when actual > target" do
      quota = goal.daily_quotas.find_by(date: Date.yesterday)
      quota.update!(actual_pages: 30)
      disc = goal.yesterday_discrepancy
      expect(disc[:type]).to eq(:ahead)
      expect(disc[:pages]).to eq(10)
    end

    it "returns nil when exactly on target" do
      quota = goal.daily_quotas.find_by(date: Date.yesterday)
      quota.update!(actual_pages: 20)
      expect(goal.yesterday_discrepancy).to be_nil
    end

    it "returns nil when already missed" do
      quota = goal.daily_quotas.find_by(date: Date.yesterday)
      quota.update!(status: :missed)
      expect(goal.yesterday_discrepancy).to be_nil
    end
  end

  describe "#has_unresolved_discrepancy?" do
    let(:goal) do
      g = create(:reading_goal, user: user, book: book, status: :active,
                 started_on: 3.days.ago.to_date, target_completion_date: 7.days.from_now.to_date)
      g.daily_quotas.destroy_all
      (3.days.ago.to_date..7.days.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end
      g
    end

    it "returns true when there is an unacknowledged discrepancy" do
      goal.daily_quotas.find_by(date: Date.yesterday).update!(actual_pages: 10)
      expect(goal.has_unresolved_discrepancy?).to be true
    end

    it "returns false after acknowledging" do
      goal.daily_quotas.find_by(date: Date.yesterday).update!(actual_pages: 10)
      goal.update!(discrepancy_acknowledged_on: Date.current)
      expect(goal.has_unresolved_discrepancy?).to be false
    end
  end

  describe "#snap_period_label" do
    it "returns '1-week read' for 7-day goals" do
      goal = build(:reading_goal, started_on: Date.current,
                   target_completion_date: Date.current + 6)
      expect(goal.snap_period_label).to eq("1-week read")
    end

    it "returns '2-week read' for 14-day goals" do
      goal = build(:reading_goal, started_on: Date.current,
                   target_completion_date: Date.current + 13)
      expect(goal.snap_period_label).to eq("2-week read")
    end

    it "returns a month label for calendar month durations" do
      start = Date.new(2026, 3, 1)
      goal = build(:reading_goal, started_on: start,
                   target_completion_date: start + 1.month - 1)
      expect(goal.snap_period_label).to eq("1-month read")
    end

    it "handles short durations" do
      goal = build(:reading_goal, started_on: Date.current,
                   target_completion_date: Date.current + 2)
      expect(goal.snap_period_label).to eq("3-day read")
    end
  end

  describe "#reschedule!" do
    let(:goal) do
      g = create(:reading_goal, user: user, book: book, status: :active,
                 started_on: 1.week.ago.to_date, target_completion_date: 1.week.from_now.to_date)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 25, actual_pages: 0, status: :pending)
      end
      g
    end

    context "when user has read today" do
      before do
        create(:reading_session, :completed, user: user, book: book,
               started_at: Time.current - 30.minutes, ended_at: Time.current)
      end

      it "preserves today's quota" do
        today_quota = goal.daily_quotas.find_by(date: Date.current)
        original_target = today_quota.target_pages

        goal.reschedule!(1.week.ago.to_date, 2.weeks.from_now.to_date)

        expect(today_quota.reload.target_pages).to eq(original_target)
      end
    end

    context "when user has not read today" do
      it "regenerates today's quota" do
        today_quota = goal.daily_quotas.find_by(date: Date.current)

        goal.reschedule!(1.week.ago.to_date, 2.weeks.from_now.to_date)

        expect { today_quota.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "#quota_modification_cutoff" do
    let(:goal) do
      create(:reading_goal, user: user, book: book, status: :active,
             started_on: Date.current, target_completion_date: 1.week.from_now.to_date)
    end

    it "returns tomorrow when user has read today" do
      create(:reading_session, :completed, user: user, book: book,
             started_at: Time.current - 30.minutes, ended_at: Time.current)

      expect(goal.quota_modification_cutoff).to eq(Date.current + 1)
    end

    it "returns today when user has not read today" do
      expect(goal.quota_modification_cutoff).to eq(Date.current)
    end
  end

  describe "#on_track?" do
    it "returns true for completed goals" do
      goal = build(:reading_goal, user: user, book: book, status: :completed)
      expect(goal.on_track?).to be true
    end

    it "returns false for abandoned goals" do
      goal = build(:reading_goal, user: user, book: book, status: :abandoned)
      expect(goal.on_track?).to be false
    end
  end

  describe "#not_started?" do
    it "returns true when active but started_on is future" do
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.tomorrow, target_completion_date: 2.weeks.from_now.to_date)
      expect(goal.not_started?).to be true
    end

    it "returns false when started_on is today or past" do
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.current, target_completion_date: 2.weeks.from_now.to_date)
      expect(goal.not_started?).to be false
    end
  end

  describe "callbacks" do
    it "generates daily quotas after create for active goals" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 7.days.from_now.to_date)
      expect(goal.daily_quotas.count).to be > 0
    end

    it "does not generate quotas for queued goals" do
      goal = create(:reading_goal, user: user, book: book, status: :queued,
                    started_on: nil, target_completion_date: nil)
      expect(goal.daily_quotas.count).to eq(0)
    end
  end

  describe "#goal_reading_days" do
    it "returns 0 for queued goals" do
      goal = build(:reading_goal, user: user, book: book, status: :queued,
                   started_on: nil, target_completion_date: nil)
      expect(goal.goal_reading_days).to eq(0)
    end

    it "returns at least 1 for valid goals" do
      goal = build(:reading_goal, user: user, book: book,
                   started_on: Date.current, target_completion_date: Date.current + 1)
      expect(goal.goal_reading_days).to be >= 1
    end
  end

  describe "#progress_percentage" do
    it "returns 100 for completed goals" do
      goal = build(:reading_goal, user: user, book: book, status: :completed)
      expect(goal.progress_percentage).to eq(100)
    end

    it "delegates to book for active goals" do
      book.update!(current_page: 100) # 50% of 200
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.current, target_completion_date: 7.days.from_now.to_date)
      expect(goal.progress_percentage).to eq(book.progress_percentage)
    end
  end

  describe "#postpone!" do
    it "clears dates and sets status to queued with postponed_until" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    auto_scheduled: true, position: 1)

      goal.postpone!

      expect(goal.status).to eq("queued")
      expect(goal.started_on).to be_nil
      expect(goal.target_completion_date).to be_nil
      expect(goal.postponed_until).to be_present
      expect(goal.postponed_until).to be_monday
    end

    it "preserves auto_scheduled and position" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    auto_scheduled: true, position: 3)

      goal.postpone!

      expect(goal.auto_scheduled).to be true
      expect(goal.position).to eq(3)
    end

    it "deletes future quotas but preserves past ones" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: 3.days.ago.to_date, target_completion_date: 14.days.from_now.to_date,
                    auto_scheduled: true, position: 1)
      # Generate some quotas
      QuotaCalculator.new(goal).generate_quotas!
      past_count = goal.daily_quotas.where("date < ?", Date.current).count

      goal.postpone!

      expect(goal.daily_quotas.where("date >= ?", Date.current).count).to eq(0)
      expect(goal.daily_quotas.where("date < ?", Date.current).count).to eq(past_count)
    end

    it "sets postponed_until to the Monday after next" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    auto_scheduled: true, position: 1)

      next_monday = Date.current.beginning_of_week(:monday) + 7
      expected = next_monday + 7

      goal.postpone!

      expect(goal.postponed_until).to eq(expected)
    end
  end

  describe "#unlock!" do
    it "clears manual placement and converts to auto-scheduled" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    manually_placed: true, placement_tier: "two_weeks",
                    auto_scheduled: false)

      goal.unlock!

      expect(goal.status).to eq("queued")
      expect(goal.started_on).to be_nil
      expect(goal.target_completion_date).to be_nil
      expect(goal.manually_placed).to be false
      expect(goal.placement_tier).to be_nil
      expect(goal.auto_scheduled).to be true
    end

    it "deletes future quotas" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    manually_placed: true, placement_tier: "two_weeks",
                    auto_scheduled: false)
      QuotaCalculator.new(goal).generate_quotas!

      goal.unlock!

      expect(goal.daily_quotas.where("date >= ?", Date.current).count).to eq(0)
    end
  end

  describe "placement_tier validation" do
    it "validates placement_tier when manually_placed is true" do
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                   manually_placed: true, placement_tier: "invalid_tier")
      expect(goal).not_to be_valid
      expect(goal.errors[:placement_tier]).to include("must be a valid tier")
    end

    it "accepts valid tiers" do
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                   manually_placed: true, placement_tier: "two_weeks")
      expect(goal).to be_valid
    end

    it "does not validate tier when not manually placed" do
      goal = build(:reading_goal, user: user, book: book, status: :active,
                   started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                   manually_placed: false, placement_tier: nil)
      expect(goal).to be_valid
    end
  end

  describe "#as_pipeline_data" do
    it "includes manually_placed and placement_tier" do
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: Date.current, target_completion_date: 14.days.from_now.to_date,
                    manually_placed: true, placement_tier: "two_weeks")

      data = goal.as_pipeline_data
      expect(data[:manually_placed]).to be true
      expect(data[:placement_tier]).to eq("two_weeks")
    end

    it "includes postponed_until in queued pipeline data" do
      goal = create(:reading_goal, user: user, book: book, status: :queued,
                    started_on: nil, target_completion_date: nil,
                    postponed_until: Date.current + 14)

      data = goal.as_pipeline_data
      expect(data[:postponed_until]).to eq((Date.current + 14).to_s)
    end
  end
end
