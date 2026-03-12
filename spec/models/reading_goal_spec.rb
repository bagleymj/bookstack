require "rails_helper"

RSpec.describe ReadingGoal, type: :model do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      weekend_mode: :same)
  end
  let(:book) { create(:book, user: user, last_page: 200, current_page: 1) }

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

        # Today's quota was destroyed and recreated
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
end
