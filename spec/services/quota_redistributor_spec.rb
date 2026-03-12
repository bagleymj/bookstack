require "rails_helper"

RSpec.describe QuotaRedistributor do
  let(:user) { create(:user, weekend_mode: :same) }
  let(:book) { create(:book, user: user, first_page: 1, last_page: 100, current_page: 1) }
  let(:goal) do
    g = create(:reading_goal, user: user, book: book, status: :active,
               started_on: 2.days.ago.to_date, target_completion_date: 5.days.from_now.to_date)
    g.daily_quotas.destroy_all
    (Date.current..5.days.from_now.to_date).each do |date|
      g.daily_quotas.create!(date: date, target_pages: 17, actual_pages: 0, status: :pending)
    end
    g
  end

  before { goal }

  describe "today-quota protection" do
    context "when user has completed a reading session today" do
      before do
        create(:reading_session, :completed, user: user, book: book,
               started_at: Time.current - 30.minutes, ended_at: Time.current)
      end

      it "does not modify today's quota" do
        today_quota = goal.daily_quotas.find_by(date: Date.current)
        original_target = today_quota.target_pages

        described_class.new(goal).redistribute!

        expect(today_quota.reload.target_pages).to eq(original_target)
      end

      it "distributes remaining pages minus today's committed quota to future days" do
        today_target = goal.daily_quotas.find_by(date: Date.current).target_pages

        described_class.new(goal).redistribute!

        future_quotas = goal.daily_quotas.where("date > ?", Date.current)
        expect(future_quotas.sum(:target_pages)).to eq(book.remaining_pages - today_target)
      end
    end

    context "when user has no reading session today" do
      it "includes today's quota in redistribution" do
        described_class.new(goal).redistribute!

        future_quotas = goal.daily_quotas.where("date >= ?", Date.current)
        expect(future_quotas.sum(:target_pages)).to eq(book.remaining_pages)
      end
    end
  end
end
