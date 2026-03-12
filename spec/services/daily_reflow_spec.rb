require "rails_helper"

RSpec.describe DailyReflow do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      weekend_mode: :same)
  end

  let(:book) { create(:book, user: user, last_page: 100, current_page: 1) }

  let(:started_on) { 3.days.ago.to_date }
  let(:target_completion_date) { 4.days.from_now.to_date }

  let(:goal) do
    g = create(:reading_goal, user: user, book: book, status: :active,
               started_on: started_on, target_completion_date: target_completion_date)
    g.daily_quotas.destroy_all
    (started_on..target_completion_date).each do |date|
      g.daily_quotas.create!(date: date, target_pages: 13, actual_pages: 0, status: :pending)
    end
    g
  end

  # Force goal creation and clear user association cache before each test
  before do
    goal
    user.reload
  end

  describe "#needs_reflow?" do
    it "returns true when quotas_generated_on is nil" do
      user.update_column(:quotas_generated_on, nil)
      expect(DailyReflow.new(user).needs_reflow?).to be true
    end

    it "returns true when quotas_generated_on is yesterday" do
      user.update_column(:quotas_generated_on, Date.yesterday)
      expect(DailyReflow.new(user).needs_reflow?).to be true
    end

    it "returns false when quotas_generated_on is today" do
      user.update_column(:quotas_generated_on, Date.current)
      expect(DailyReflow.new(user).needs_reflow?).to be false
    end
  end

  describe "#reflow!" do
    it "marks past incomplete quotas as missed" do
      DailyReflow.new(user).reflow!

      past_quotas = DailyQuota.where(reading_goal_id: goal.id).where("date < ?", Date.current)
      expect(past_quotas.count).to be > 0
      past_quotas.each do |q|
        expect(q.status).to eq("missed")
      end
    end

    it "redistributes remaining pages across future quotas" do
      DailyReflow.new(user).reflow!

      future_quotas = DailyQuota.where(reading_goal_id: goal.id)
                                .where("date >= ?", Date.current)
      expect(future_quotas.sum(:target_pages)).to eq(book.remaining_pages)
    end

    it "updates quotas_generated_on to today" do
      user.update_column(:quotas_generated_on, nil)
      DailyReflow.new(user).reflow!
      expect(user.reload.quotas_generated_on).to eq(Date.current)
    end

    it "adjusts for pages already read" do
      book.update!(current_page: 50) # Read 49 pages, 50 remaining
      DailyReflow.new(user).reflow!

      future_quotas = DailyQuota.where(reading_goal_id: goal.id)
                                .where("date >= ?", Date.current)
      expect(future_quotas.sum(:target_pages)).to eq(50)
    end
  end

  describe "#reflow_if_stale!" do
    it "reflows when stale" do
      user.update_column(:quotas_generated_on, Date.yesterday)
      DailyReflow.new(user).reflow_if_stale!
      expect(user.reload.quotas_generated_on).to eq(Date.current)
    end

    it "skips when fresh" do
      user.update_column(:quotas_generated_on, Date.current)
      original_targets = DailyQuota.where(reading_goal_id: goal.id).order(:date).pluck(:target_pages)
      DailyReflow.new(user).reflow_if_stale!
      expect(DailyQuota.where(reading_goal_id: goal.id).order(:date).pluck(:target_pages)).to eq(original_targets)
    end
  end

  # ─── Today-Quota Protection ─────────────────────────────────

  describe "today-quota protection" do
    context "when user has completed a reading session today" do
      before do
        create(:reading_session, :completed, user: user, book: book,
               started_at: Time.current - 30.minutes, ended_at: Time.current)
      end

      it "does not modify today's quota during redistribute" do
        original_today = goal.daily_quotas.find_by(date: Date.current)
        original_target = original_today.target_pages

        DailyReflow.new(user).reflow!

        expect(original_today.reload.target_pages).to eq(original_target)
      end

      it "redistributes remaining pages across tomorrow onward" do
        book.update!(current_page: 50) # 50 remaining
        today_target = goal.daily_quotas.find_by(date: Date.current).target_pages

        DailyReflow.new(user).reflow!

        future_quotas = goal.daily_quotas.where("date > ?", Date.current)
        expect(future_quotas.sum(:target_pages)).to eq(50 - today_target)
      end
    end

    context "when user has no reading session today" do
      it "includes today's quota in redistribution" do
        book.update!(current_page: 50) # 50 remaining

        DailyReflow.new(user).reflow!

        future_quotas = goal.daily_quotas.where("date >= ?", Date.current)
        expect(future_quotas.sum(:target_pages)).to eq(50)
      end
    end
  end

  # ─── Scheduler Integration ───────────────────────────────────

  describe "scheduler integration in heijunka mode" do
    let(:heijunka_user) do
      create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: Date.current.beginning_of_year,
        default_reading_speed_wpm: 250,
        max_concurrent_books: 3,
        weekend_mode: :same)
    end

    before { heijunka_user.update_column(:quotas_generated_on, nil) }

    it "always calls ReadingListScheduler#schedule! in heijunka mode" do
      # Active goal, no queued books — schedule! should still be called
      active_book = create(:book, user: heijunka_user, last_page: 200, current_page: 1)
      g = create(:reading_goal, user: heijunka_user, book: active_book,
                 status: :active, started_on: 1.week.ago.to_date,
                 target_completion_date: 1.week.from_now.to_date,
                 auto_scheduled: true, position: 1)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end

      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:schedule!).and_return(Set.new)

      heijunka_user.reload
      DailyReflow.new(heijunka_user).reflow!

      expect(scheduler).to have_received(:schedule!)
    end

    it "skips redistribution for goals handled by the scheduler" do
      active_book = create(:book, user: heijunka_user, last_page: 200, current_page: 1)
      g = create(:reading_goal, user: heijunka_user, book: active_book,
                 status: :active, started_on: 1.week.ago.to_date,
                 target_completion_date: 1.week.from_now.to_date,
                 auto_scheduled: true, position: 1)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end

      # Scheduler says it handled this goal
      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:schedule!).and_return(Set.new([g.id]))

      heijunka_user.reload
      original_quotas = g.daily_quotas.where("date >= ?", Date.current).order(:date).pluck(:target_pages)

      DailyReflow.new(heijunka_user).reflow!

      # Quotas should not have been redistributed (scheduler handled it)
      current_quotas = g.daily_quotas.where("date >= ?", Date.current).order(:date).pluck(:target_pages)
      expect(current_quotas).to eq(original_quotas)
    end

    it "redistributes goals not handled by the scheduler" do
      active_book = create(:book, user: heijunka_user, last_page: 200, current_page: 50)
      g = create(:reading_goal, user: heijunka_user, book: active_book,
                 status: :active, started_on: 1.week.ago.to_date,
                 target_completion_date: 1.week.from_now.to_date,
                 auto_scheduled: true, position: 1)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end

      # Scheduler returns empty set — didn't handle this goal
      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:schedule!).and_return(Set.new)

      heijunka_user.reload
      DailyReflow.new(heijunka_user).reflow!

      # Quotas should be redistributed to match remaining pages
      future_quotas = DailyQuota.where(reading_goal_id: g.id)
                                .where("date >= ?", Date.current)
                                .where.not(status: :missed)
      expect(future_quotas.sum(:target_pages)).to eq(active_book.remaining_pages)
    end

    it "does not call schedule! when not in heijunka mode" do
      non_heijunka_user = create(:user, reading_pace_type: nil, reading_pace_value: nil, weekend_mode: :same)
      non_heijunka_user.update_column(:quotas_generated_on, nil)

      book = create(:book, user: non_heijunka_user, last_page: 100, current_page: 1)
      g = create(:reading_goal, user: non_heijunka_user, book: book, status: :active,
                 started_on: 3.days.ago.to_date, target_completion_date: 4.days.from_now.to_date)
      g.daily_quotas.destroy_all
      (Date.current..4.days.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end
      non_heijunka_user.reload

      expect(ReadingListScheduler).not_to receive(:new)
      DailyReflow.new(non_heijunka_user).reflow!
    end
  end
end
