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
end
