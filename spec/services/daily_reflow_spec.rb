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

  # ─── Tier Promotion ─────────────────────────────────────────

  describe "tier promotion" do
    # Dense book: 300 pages, 250 wpp, user reads at 250 wpm
    # remaining_words = 299 * 250 = 74,750
    # remaining_minutes = 74750 / 250 = 299
    let(:dense_book) { create(:book, user: promo_user, last_page: 300, current_page: 1) }

    let(:promo_user) do
      create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 52,
        weekend_mode: :same)
    end

    before do
      promo_user.update_column(:quotas_generated_on, nil)
      # Stub the scheduler so promotion tests focus on promotion behavior only
      allow_any_instance_of(ReadingListScheduler).to receive(:schedule!)
    end

    context "when daily load exceeds target" do
      before do
        allow_any_instance_of(DailyReflow).to receive(:derived_daily_target).and_return(40)
      end

      let(:spiking_goal) do
        # 3 remaining reading days: 299 min / 3 = 99.7 min/day > 40 * 1.1 = 44
        g = create(:reading_goal, user: promo_user, book: dense_book, status: :active,
                   started_on: 3.days.ago.to_date,
                   target_completion_date: Date.current + 2,
                   auto_scheduled: true, position: 1)
        g.daily_quotas.destroy_all
        (g.started_on..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 60, actual_pages: 0, status: :pending)
        end
        g
      end

      before { spiking_goal; promo_user.reload }

      it "extends the goal's target_completion_date by one week" do
        original_end = spiking_goal.target_completion_date
        DailyReflow.new(promo_user).reflow!
        # After extension: 299 / 10 = 29.9 min/day < 44 → one extension suffices
        expect(spiking_goal.reload.target_completion_date).to eq(original_end + 7)
      end

      it "regenerates quotas across the extended range" do
        DailyReflow.new(promo_user).reflow!
        spiking_goal.reload

        future_quotas = DailyQuota.where(reading_goal_id: spiking_goal.id)
                                  .where("date >= ?", Date.current)
                                  .order(:date)
        expect(future_quotas.last.date).to eq(spiking_goal.target_completion_date)
        expect(future_quotas.sum(:target_pages)).to eq(dense_book.remaining_pages)
      end
    end

    context "when daily load is within target" do
      before do
        allow_any_instance_of(DailyReflow).to receive(:derived_daily_target).and_return(40)
      end

      let(:comfortable_goal) do
        # 21 remaining reading days: 299 min / 21 = 14.2 min/day < 44
        g = create(:reading_goal, user: promo_user, book: dense_book, status: :active,
                   started_on: 7.days.ago.to_date,
                   target_completion_date: Date.current + 20,
                   auto_scheduled: true, position: 1)
        g.daily_quotas.destroy_all
        (Date.current..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 15, actual_pages: 0, status: :pending)
        end
        g
      end

      before { comfortable_goal; promo_user.reload }

      it "does not extend the goal" do
        original_end = comfortable_goal.target_completion_date
        DailyReflow.new(promo_user).reflow!
        expect(comfortable_goal.reload.target_completion_date).to eq(original_end)
      end
    end

    context "with a very low target requiring multiple extensions" do
      before do
        allow_any_instance_of(DailyReflow).to receive(:derived_daily_target).and_return(10)
      end

      let(:heavy_goal) do
        # 3 remaining days: ~100 min/day > 10 * 1.1 = 11
        # Needs several weekly extensions to bring share under target
        g = create(:reading_goal, user: promo_user, book: dense_book, status: :active,
                   started_on: 3.days.ago.to_date,
                   target_completion_date: Date.current + 2,
                   auto_scheduled: true, position: 1)
        g.daily_quotas.destroy_all
        (Date.current..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 100, actual_pages: 0, status: :pending)
        end
        g
      end

      before { heavy_goal; promo_user.reload }

      it "extends multiple times until load is under target" do
        original_end = heavy_goal.target_completion_date
        DailyReflow.new(promo_user).reflow!
        heavy_goal.reload

        # Must have extended more than once
        expect(heavy_goal.target_completion_date).to be > original_end + 7

        # Final daily share should be under target * tolerance
        remaining_days = (heavy_goal.target_completion_date - Date.current).to_i + 1
        final_share = 299.0 / remaining_days  # 299 remaining minutes for this book
        expect(final_share).to be < 10 * DailyReflow::SPIKE_TOLERANCE
      end
    end

    context "without heijunka mode" do
      let(:non_heijunka_user) do
        create(:user,
          reading_pace_type: nil,
          reading_pace_value: nil,
          weekend_mode: :same)
      end

      let(:non_heijunka_book) { create(:book, user: non_heijunka_user, last_page: 300, current_page: 1) }

      let(:unmanaged_goal) do
        g = create(:reading_goal, user: non_heijunka_user, book: non_heijunka_book, status: :active,
                   started_on: 3.days.ago.to_date,
                   target_completion_date: Date.current + 2,
                   auto_scheduled: true, position: 1)
        g.daily_quotas.destroy_all
        (Date.current..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 100, actual_pages: 0, status: :pending)
        end
        g
      end

      before do
        unmanaged_goal
        non_heijunka_user.update_column(:quotas_generated_on, nil)
        non_heijunka_user.reload
      end

      it "skips promotion entirely" do
        original_end = unmanaged_goal.target_completion_date
        DailyReflow.new(non_heijunka_user).reflow!
        expect(unmanaged_goal.reload.target_completion_date).to eq(original_end)
      end
    end

    context "with concurrent goals causing a spike" do
      before do
        allow_any_instance_of(DailyReflow).to receive(:derived_daily_target).and_return(40)
      end

      let(:book_a) { create(:book, user: promo_user, last_page: 300, current_page: 1) }
      let(:book_b) { create(:book, user: promo_user, last_page: 150, current_page: 1) }

      let(:goal_a) do
        # 299 min / 10 days = 29.9 min/day
        g = create(:reading_goal, user: promo_user, book: book_a, status: :active,
                   started_on: 3.days.ago.to_date,
                   target_completion_date: Date.current + 9,
                   auto_scheduled: true, position: 1)
        g.daily_quotas.destroy_all
        (Date.current..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 30, actual_pages: 0, status: :pending)
        end
        g
      end

      let(:goal_b) do
        # 149 min / 5 days = 29.8 min/day
        # Total: 29.9 + 29.8 = 59.7 > 44 → spike
        g = create(:reading_goal, user: promo_user, book: book_b, status: :active,
                   started_on: 3.days.ago.to_date,
                   target_completion_date: Date.current + 4,
                   auto_scheduled: true, position: 2)
        g.daily_quotas.destroy_all
        (Date.current..g.target_completion_date).each do |date|
          g.daily_quotas.create!(date: date, target_pages: 30, actual_pages: 0, status: :pending)
        end
        g
      end

      before { goal_a; goal_b; promo_user.reload }

      it "extends the heaviest goal to resolve the spike" do
        DailyReflow.new(promo_user).reflow!

        # goal_a has higher share (29.9 vs 29.8), gets extended first
        # After extending goal_a: 299/17 = 17.6 + 29.8 = 47.4 > 44
        # Extend goal_b: 149/12 = 12.4 + 17.6 = 30.0 < 44 → stop
        expect(goal_a.reload.target_completion_date).to be > Date.current + 9
        expect(goal_b.reload.target_completion_date).to be > Date.current + 4
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

    it "calls ReadingListScheduler#schedule! when queued books exist" do
      # Create a queued book so the scheduler fires
      queued_book = create(:book, user: heijunka_user, last_page: 200, current_page: 1)
      create(:reading_goal, user: heijunka_user, book: queued_book,
             status: :queued, auto_scheduled: true, position: 1)

      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:schedule!)
      allow(scheduler).to receive(:metrics).and_return({ derived_target: 40 })

      heijunka_user.reload
      DailyReflow.new(heijunka_user).reflow!

      expect(scheduler).to have_received(:schedule!)
    end

    it "does not call schedule! when no queued books exist" do
      # Only active goals, no queued ones
      active_book = create(:book, user: heijunka_user, last_page: 200, current_page: 1)
      g = create(:reading_goal, user: heijunka_user, book: active_book,
                 status: :active, started_on: 1.week.ago.to_date,
                 target_completion_date: 1.week.from_now.to_date,
                 auto_scheduled: true, position: 1)
      g.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        g.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end

      # Stub metrics (for tier promotion) but schedule! should NOT be called
      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:schedule!)
      allow(scheduler).to receive(:metrics).and_return({ derived_target: 40 })

      heijunka_user.reload
      DailyReflow.new(heijunka_user).reflow!

      expect(scheduler).not_to have_received(:schedule!)
    end

    it "redistributes all active goals regardless of session status" do
      # Create two active goals — one with sessions, one without
      locked_book = create(:book, user: heijunka_user, last_page: 200, current_page: 50)
      unlocked_book = create(:book, user: heijunka_user, last_page: 200, current_page: 1)

      locked_goal = create(:reading_goal, user: heijunka_user, book: locked_book,
                           status: :active, started_on: 1.week.ago.to_date,
                           target_completion_date: 1.week.from_now.to_date,
                           auto_scheduled: true, position: 1)
      unlocked_goal = create(:reading_goal, user: heijunka_user, book: unlocked_book,
                             status: :active, started_on: 1.week.ago.to_date,
                             target_completion_date: 1.week.from_now.to_date,
                             auto_scheduled: true, position: 2)

      # Clear auto-generated quotas and add manual ones
      locked_goal.daily_quotas.destroy_all
      unlocked_goal.daily_quotas.destroy_all
      (Date.current..1.week.from_now.to_date).each do |date|
        locked_goal.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
        unlocked_goal.daily_quotas.create!(date: date, target_pages: 20, actual_pages: 0, status: :pending)
      end

      # Lock one goal with a reading session
      create(:reading_session, user: heijunka_user, book: locked_book,
             start_page: 1, end_page: 50, pages_read: 49,
             started_at: 1.day.ago, ended_at: 1.day.ago + 30.minutes,
             duration_seconds: 1800)

      # Stub the scheduler (no queued books, so schedule! won't fire)
      scheduler = instance_double(ReadingListScheduler)
      allow(ReadingListScheduler).to receive(:new).with(heijunka_user).and_return(scheduler)
      allow(scheduler).to receive(:metrics).and_return({ derived_target: 40 })

      heijunka_user.reload
      DailyReflow.new(heijunka_user).reflow!

      # Both goals should have redistributed quotas (sum = remaining pages)
      locked_quotas = DailyQuota.where(reading_goal_id: locked_goal.id)
                                .where("date >= ?", Date.current)
                                .where.not(status: :missed)
      expect(locked_quotas.sum(:target_pages)).to eq(locked_book.remaining_pages)

      unlocked_quotas = DailyQuota.where(reading_goal_id: unlocked_goal.id)
                                  .where("date >= ?", Date.current)
                                  .where.not(status: :missed)
      expect(unlocked_quotas.sum(:target_pages)).to eq(unlocked_book.remaining_pages)
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
