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
end
