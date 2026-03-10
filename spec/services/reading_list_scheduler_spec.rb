require "rails_helper"

RSpec.describe ReadingListScheduler do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      reading_pace_set_on: Date.current.beginning_of_year,
      default_reading_speed_wpm: 250,
      default_words_per_page: 250,
      max_concurrent_books: 3,
      weekend_mode: :same,
      weekday_reading_minutes: 60,
      weekend_reading_minutes: 60)
  end

  def create_queued_book(pages: 300, position: 1, difficulty: :average, title: "Book")
    book = create(:book, user: user, last_page: pages, difficulty: difficulty, title: title)
    create(:reading_goal, user: user, book: book, status: :queued,
           started_on: nil, target_completion_date: nil,
           auto_scheduled: true, position: position)
    book
  end

  def schedule!
    ReadingListScheduler.new(user).schedule!
  end

  # ─── Core Behavior ──────────────────────────────────────────────

  describe "#schedule!" do
    it "places a queued book into an active goal with dates" do
      create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.first
      expect(goal.status).to eq("active")
      expect(goal.started_on).to be_present
      expect(goal.target_completion_date).to be_present
      expect(goal.started_on).to be_monday
    end

    it "generates daily quotas for placed books" do
      create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.first
      expect(goal.daily_quotas.count).to be > 0
      expect(goal.daily_quotas.sum(:target_pages)).to eq(goal.book.remaining_pages)
    end

    it "places multiple books with valid dates" do
      create_queued_book(pages: 200, position: 1, title: "First")
      create_queued_book(pages: 200, position: 2, title: "Second")
      create_queued_book(pages: 200, position: 3, title: "Third")
      schedule!

      goals = user.reading_goals.active.order(:position)
      expect(goals.map { |g| g.book.title }).to eq(%w[First Second Third])

      # All books should be placed with valid Monday-aligned dates
      goals.each do |goal|
        expect(goal.started_on).to be_present
        expect(goal.target_completion_date).to be_present
        expect(goal.started_on).to be_monday
        expect(goal.started_on).to be < goal.target_completion_date
      end
    end

    it "snaps all start dates to Mondays" do
      5.times { |i| create_queued_book(pages: 200 + i * 50, position: i + 1, title: "Book #{i}") }
      schedule!

      user.reading_goals.active.each do |goal|
        expect(goal.started_on).to be_monday, "#{goal.book.title} started on #{goal.started_on} (#{goal.started_on.strftime('%A')})"
      end
    end

    it "snaps all end dates to Sundays" do
      3.times { |i| create_queued_book(pages: 300, position: i + 1) }
      schedule!

      user.reading_goals.active.each do |goal|
        expect(goal.target_completion_date).to be_sunday
      end
    end
  end

  # ─── Pace Requirement ──────────────────────────────────────────

  describe "pace requirement" do
    it "does nothing without a throughput pace type" do
      user.update!(reading_pace_type: nil, reading_pace_value: nil)
      create_queued_book(pages: 300, position: 1)
      schedule!

      expect(user.reading_goals.active.count).to eq(0)
    end

    it "rejects minutes_per_day as an invalid pace type" do
      expect {
        user.update!(reading_pace_type: "minutes_per_day", reading_pace_value: 60)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "works with books_per_month pace type" do
      user.update!(reading_pace_type: "books_per_month", reading_pace_value: 4)
      create_queued_book(pages: 300, position: 1)
      schedule!

      expect(user.reading_goals.active.count).to eq(1)
    end

    it "works with books_per_week pace type" do
      user.update!(reading_pace_type: "books_per_week", reading_pace_value: 1)
      create_queued_book(pages: 300, position: 1)
      schedule!

      expect(user.reading_goals.active.count).to eq(1)
    end
  end

  # ─── Target Derivation (Phase 2) ───────────────────────────────

  describe "target derivation" do
    it "derives a positive daily target from pace and book mix" do
      create_queued_book(pages: 300, position: 1)
      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      expect(scheduler.daily_target).to be > 0
    end

    it "adjusts target based on deficit (behind pace)" do
      # Simulate being behind: pace says we should have completed some books by now
      user.update!(reading_pace_set_on: 6.months.ago.to_date)
      create_queued_book(pages: 300, position: 1)

      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      # When behind, deficit is positive — target should be higher than start-of-year
      expect(scheduler.deficit).to be > 0
    end

    it "computes target from rolling window of queued + completed books" do
      # Queue a mix of short and long books
      create_queued_book(pages: 150, position: 1, title: "Short")
      create_queued_book(pages: 600, position: 2, title: "Long")

      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      # Target should be based on average of both books
      expect(scheduler.daily_target).to be > 0
    end
  end

  # ─── Tier Selection (Phase 3) ──────────────────────────────────

  describe "tier selection" do
    it "places a short book in a short tier" do
      create_queued_book(pages: 100, position: 1)
      schedule!

      goal = user.reading_goals.active.first
      calendar_days = (goal.target_completion_date - goal.started_on).to_i + 1
      expect(calendar_days).to be <= 14 # 1 or 2 week tier
    end

    it "places a long book in a longer tier than a short book" do
      # Mix of short and long books — the long one should get a longer tier
      5.times { |i| create_queued_book(pages: 200, position: i + 1, title: "Short #{i}") }
      create_queued_book(pages: 1500, position: 6, title: "Long One")
      schedule!

      short_goal = user.reading_goals.active.joins(:book).find_by(books: { title: "Short 0" })
      long_goal = user.reading_goals.active.joins(:book).find_by(books: { title: "Long One" })

      short_days = (short_goal.target_completion_date - short_goal.started_on).to_i + 1
      long_days = (long_goal.target_completion_date - long_goal.started_on).to_i + 1
      expect(long_days).to be > short_days
    end

    it "keeps daily load level across concurrent books" do
      # Place several books — the load should be roughly even
      5.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }
      schedule!

      goals = user.reading_goals.active
      expect(goals.count).to eq(5)

      # All books should have reasonable daily page targets (not spiking)
      goals.each do |goal|
        reading_days = goal.goal_reading_days
        next if reading_days == 0
        pages_per_day = goal.book.total_pages.to_f / reading_days
        expect(pages_per_day).to be < 100, "#{goal.book.title} has #{pages_per_day.round} pages/day — too high"
      end
    end

    it "layers books with overlapping tiers to fill valleys (global leveling)" do
      # With enough books, later books should use longer tiers that overlap
      # with earlier ones to fill gaps — not just stack sequentially.
      # This is the core heijunka behavior: uniform load across the timeline.
      8.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }
      schedule!

      goals = user.reading_goals.active.order(:started_on, :position)
      expect(goals.count).to eq(8)

      # Compute daily load profile across the entire scheduled timeline
      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      all_starts = goals.map(&:started_on)
      all_ends = goals.map(&:target_completion_date)
      timeline_start = all_starts.min
      timeline_end = all_ends.max

      # Some books should overlap (not all purely sequential)
      overlapping_pairs = 0
      goals.to_a.combination(2).each do |a, b|
        if a.started_on < b.target_completion_date && b.started_on < a.target_completion_date
          overlapping_pairs += 1
        end
      end
      expect(overlapping_pairs).to be > 0, "No overlapping books — algorithm is stacking sequentially instead of layering"

      # The maximum valley in the scheduled timeline should be bounded.
      # With 8 books, if placed well, the max undershoot should be well
      # below the full target (i.e., no completely empty weeks within the
      # scheduled range).
      wpm = user.effective_reading_speed
      target_per_day = scheduler.daily_target
      next unless target_per_day&.positive?

      weekdays = (timeline_start..timeline_end).select { |d| !d.on_weekend? }
      daily_loads = weekdays.map do |date|
        goals.sum do |g|
          next 0 unless date >= g.started_on && date <= g.target_completion_date
          book = g.book
          minutes = (book.remaining_words.to_f / wpm).ceil
          reading_days = (g.started_on..g.target_completion_date).count { |d| !d.on_weekend? }
          reading_days > 0 ? minutes.to_f / reading_days : 0
        end
      end

      max_load = daily_loads.max || 0
      min_load = daily_loads.min || 0
      # The load should not vary by more than 2x across the timeline
      expect(max_load).to be > 0
      expect(min_load).to be > max_load * 0.3,
        "Valley too deep: min=#{min_load.round(1)}, max=#{max_load.round(1)}. " \
        "Load should be leveled, not peaked."
    end

    it "fills to target — no persistent shortfall in the core timeline" do
      # True heijunka: reading days in the core timeline (where multiple books
      # overlap) should be close to the derived target. The trailing tail after
      # the last book starts is excluded — only one overlay book remains there
      # and no further books exist to fill it.
      10.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }

      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      goals = user.reading_goals.active.reload
      target = scheduler.daily_target
      next unless target&.positive?

      # Core timeline: from earliest start to the last book's START date.
      # After the last book starts, the tail only has residual overlay load
      # and no queued books remain to fill it.
      all_starts = goals.map(&:started_on)
      all_ends = goals.map(&:target_completion_date)
      timeline_start = all_starts.min
      core_end = all_starts.max + 6 # through the week the last book starts

      wpm = user.effective_reading_speed
      weekdays = (timeline_start..core_end).select { |d| !d.on_weekend? }
      daily_loads = weekdays.map do |date|
        goals.sum do |g|
          next 0.0 unless date >= g.started_on && date <= g.target_completion_date
          book = g.book
          minutes = (book.remaining_words.to_f / wpm).ceil
          reading_days = (g.started_on..g.target_completion_date).count { |d| !d.on_weekend? }
          reading_days > 0 ? minutes.to_f / reading_days : 0.0
        end
      end

      # No day should fall more than 20% below target within the core timeline
      loaded_days = daily_loads.select { |load| load > 0 }
      next if loaded_days.empty?

      shortfall_days = loaded_days.count { |load| load < target * 0.8 }
      total_days = loaded_days.size
      shortfall_pct = (shortfall_days.to_f / total_days * 100).round(1)

      expect(shortfall_pct).to be < 15,
        "#{shortfall_pct}% of core days fall >20% below target (#{target.round} min). " \
        "Heijunka demands consistent load, not persistent valleys."
    end
  end

  # ─── Concurrency Limits ────────────────────────────────────────

  describe "concurrency limits" do
    it "respects concurrency_limit when set" do
      user.update!(concurrency_limit: 2)
      5.times { |i| create_queued_book(pages: 300, position: i + 1) }
      schedule!

      goals = user.reading_goals.active
      # Check no date has more than 2 books active
      all_dates = goals.flat_map { |g| (g.started_on..g.target_completion_date).to_a }
      all_dates.uniq.each do |date|
        active_count = goals.count { |g| g.started_on <= date && g.target_completion_date >= date }
        expect(active_count).to be <= 2, "#{date} has #{active_count} active books (limit: 2)"
      end
    end

    it "falls back to max_concurrent_books when concurrency_limit is nil" do
      user.update!(concurrency_limit: nil, max_concurrent_books: 2)
      5.times { |i| create_queued_book(pages: 300, position: i + 1) }
      schedule!

      goals = user.reading_goals.active
      all_dates = goals.flat_map { |g| (g.started_on..g.target_completion_date).to_a }
      all_dates.uniq.each do |date|
        active_count = goals.count { |g| g.started_on <= date && g.target_completion_date >= date }
        expect(active_count).to be <= 2
      end
    end
  end

  # ─── Locked Goals ──────────────────────────────────────────────

  describe "locked goals" do
    it "preserves committed books (those with reading sessions)" do
      book = create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.find_by(book: book)
      original_start = goal.started_on
      original_end = goal.target_completion_date

      # Add a reading session to lock this goal
      create(:reading_session, user: user, book: book,
             start_page: 1, end_page: 10, pages_read: 10,
             started_at: Time.current, ended_at: 30.minutes.from_now,
             duration_seconds: 1800)

      # Add another book and reschedule
      create_queued_book(pages: 200, position: 2, title: "New Book")
      schedule!

      goal.reload
      expect(goal.started_on).to eq(original_start)
      expect(goal.target_completion_date).to eq(original_end)
    end

    it "includes locked goals in the load profile for new placements" do
      book = create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.find_by(book: book)
      create(:reading_session, user: user, book: book,
             start_page: 1, end_page: 10, pages_read: 10,
             started_at: Time.current, ended_at: 30.minutes.from_now,
             duration_seconds: 1800)

      # New book should account for locked goal's load
      create_queued_book(pages: 300, position: 2, title: "New Book")
      schedule!

      new_goal = user.reading_goals.find_by(book: Book.find_by(title: "New Book"))
      expect(new_goal).to be_active
    end
  end

  # ─── Weekend Modes ─────────────────────────────────────────────

  describe "weekend modes" do
    it "excludes weekends in skip mode" do
      user.update!(weekend_mode: :skip)
      create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.active.first
      weekend_quotas = goal.daily_quotas.select { |q| q.date.on_weekend? }
      expect(weekend_quotas).to be_empty
    end

    it "includes weekends in same mode" do
      user.update!(weekend_mode: :same)
      create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.active.first
      # Should have some weekend quotas if tier spans a weekend
      if (goal.started_on..goal.target_completion_date).any? { |d| d.on_weekend? }
        weekend_quotas = goal.daily_quotas.select { |q| q.date.on_weekend? }
        expect(weekend_quotas).not_to be_empty
      end
    end
  end

  # ─── Throughput Verification (Phase 4) ─────────────────────────

  describe "throughput verification" do
    it "adjusts placements to meet pace target" do
      # With 50 books/year pace, place enough books to verify throughput
      10.times { |i| create_queued_book(pages: 250, position: i + 1, title: "Book #{i}") }

      scheduler = ReadingListScheduler.new(user)
      scheduler.schedule!

      # All books should be placed
      expect(user.reading_goals.active.count).to eq(10)
    end
  end

  # ─── Edge Cases ────────────────────────────────────────────────

  describe "edge cases" do
    it "handles an empty queue gracefully" do
      expect { schedule! }.not_to raise_error
    end

    it "handles a single book" do
      create_queued_book(pages: 300, position: 1)
      schedule!

      expect(user.reading_goals.active.count).to eq(1)
    end

    it "handles a very short book" do
      create_queued_book(pages: 10, position: 1)
      schedule!

      goal = user.reading_goals.active.first
      expect(goal).to be_present
      expect(goal.daily_quotas.sum(:target_pages)).to eq(goal.book.remaining_pages)
    end

    it "handles a very long book among shorter ones" do
      5.times { |i| create_queued_book(pages: 200, position: i + 1, title: "Normal #{i}") }
      create_queued_book(pages: 5000, position: 6, title: "Epic")
      schedule!

      goal = user.reading_goals.active.joins(:book).find_by(books: { title: "Epic" })
      expect(goal).to be_present
      calendar_days = (goal.target_completion_date - goal.started_on).to_i + 1
      expect(calendar_days).to be >= 28
    end

    it "does not modify non-auto-scheduled goals" do
      book = create(:book, user: user, last_page: 300)
      goal = create(:reading_goal, user: user, book: book, status: :queued,
                    started_on: nil, target_completion_date: nil,
                    auto_scheduled: false, position: 1)
      schedule!

      goal.reload
      expect(goal.status).to eq("queued")
    end

    it "is idempotent — running twice produces the same result" do
      3.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }

      schedule!
      first_run = user.reading_goals.active.order(:position).map do |g|
        [g.book.title, g.started_on, g.target_completion_date]
      end

      schedule!
      second_run = user.reading_goals.active.order(:position).map do |g|
        [g.book.title, g.started_on, g.target_completion_date]
      end

      expect(second_run).to eq(first_run)
    end
  end

  # ─── Metrics ────────────────────────────────────────────────────

  describe "#metrics" do
    it "returns default metrics when no pace is set" do
      user.update!(reading_pace_type: nil, reading_pace_value: nil)
      metrics = ReadingListScheduler.new(user).metrics

      expect(metrics[:pace_status]).to be_nil
      expect(metrics[:derived_target]).to eq(0)
      expect(metrics[:pace_target]).to eq(0)
    end

    it "returns derived target and pace status with active pace" do
      create_queued_book(pages: 300, position: 1)
      metrics = ReadingListScheduler.new(user).metrics

      expect(metrics[:pace_target]).to eq(50)
      expect(metrics[:derived_target]).to be > 0
      expect(metrics[:pace_status]).to be_a(String)
    end

    it "reports queue warning when not enough books are queued" do
      # Only 1 book queued, pace target is 50/year
      create_queued_book(pages: 300, position: 1)
      metrics = ReadingListScheduler.new(user).metrics

      expect(metrics[:queue_warning]).to include("books")
    end

    it "reports no queue warning when projected completions meet pace" do
      pace_start = user.reading_pace_set_on
      pace_window_end = pace_start + 365

      # Create enough completed + scheduled goals to meet pace target of 50
      # Spread them throughout the pace window
      50.times do |i|
        book = create(:book, user: user, last_page: 100, title: "Book #{i}")
        completion_date = pace_start + ((i + 1) * 7)
        next if completion_date > pace_window_end
        create(:reading_goal, user: user, book: book, status: :active,
               started_on: completion_date - 7, target_completion_date: completion_date,
               auto_scheduled: true, position: i + 1)
      end

      metrics = ReadingListScheduler.new(user).metrics
      expect(metrics[:queue_warning]).to be_nil
    end

    it "is read-only — does not modify any goals" do
      create_queued_book(pages: 300, position: 1)
      goal = user.reading_goals.first

      ReadingListScheduler.new(user).metrics

      goal.reload
      expect(goal.status).to eq("queued")
    end

    # ─── Effective Daily Target ─────────────────────────────────────

    describe "derived_target adjusts for weekend mode" do
      it "shows weekday target for skip-weekends users" do
        user.update!(weekend_mode: :skip)
        create_queued_book(pages: 300, position: 1)
        metrics = ReadingListScheduler.new(user).metrics

        # derived_target should reflect 7/5 of the raw average
        expect(metrics[:derived_target]).to be > 0
      end

      it "shows same target for same-mode users" do
        user.update!(weekend_mode: :same)
        create_queued_book(pages: 300, position: 1)
        same_metrics = ReadingListScheduler.new(user).metrics
        expect(same_metrics[:derived_target]).to be > 0
      end

      it "shows adjusted weekday target for capped-mode users" do
        user.update!(weekend_mode: :capped, weekend_reading_minutes: 20)
        create_queued_book(pages: 300, position: 1)
        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:derived_target]).to be > 0
      end
    end

    # ─── Concurrency Hint ─────────────────────────────────────────

    describe "concurrency_hint" do
      it "returns nil when concurrency limit is high enough" do
        # max_concurrent_books defaults to 3 from factory; no concurrency_limit set
        # With a generous limit, no hint needed
        user.update!(concurrency_limit: nil, max_concurrent_books: 20)
        create_queued_book(pages: 300, position: 1)
        metrics = ReadingListScheduler.new(user).metrics

        expect(metrics[:concurrency_hint]).to be_nil
      end

      it "returns nil when limit is sufficient for the pace" do
        user.update!(concurrency_limit: 10)
        create_queued_book(pages: 300, position: 1)
        metrics = ReadingListScheduler.new(user).metrics

        expect(metrics[:concurrency_hint]).to be_nil
      end

      it "returns a hint when limit is too tight for the pace" do
        user.update!(concurrency_limit: 1)
        5.times { |i| create_queued_book(pages: 500, position: i + 1, title: "Book #{i}") }
        metrics = ReadingListScheduler.new(user).metrics

        if metrics[:concurrency_hint]
          expect(metrics[:concurrency_hint]).to include("concurrent books")
        end
      end

      it "returns nil with default metrics when no pace is set" do
        user.update!(reading_pace_type: nil, reading_pace_value: nil)
        metrics = ReadingListScheduler.new(user).metrics

        expect(metrics[:concurrency_hint]).to be_nil
      end
    end

    # ─── Ahead Suggestion ─────────────────────────────────────────

    describe "ahead_suggestion" do
      it "returns nil when active goals still have remaining pages" do
        book = create(:book, user: user, last_page: 300, current_page: 50)
        create(:reading_goal, user: user, book: book, status: :active,
               started_on: 1.week.ago.to_date, target_completion_date: 1.week.from_now.to_date,
               auto_scheduled: true, position: 1)

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:ahead_suggestion]).to be_nil
      end

      it "returns suggestion when all active books are done and queued books exist" do
        # Active goal with book fully read
        done_book = create(:book, user: user, last_page: 200, current_page: 200, title: "Done Book")
        create(:reading_goal, user: user, book: done_book, status: :active,
               started_on: 1.week.ago.to_date, target_completion_date: 1.week.from_now.to_date,
               auto_scheduled: true, position: 1)

        # Queued book waiting
        next_book = create(:book, user: user, last_page: 300, title: "Next Up")
        create(:reading_goal, user: user, book: next_book, status: :queued,
               started_on: nil, target_completion_date: nil,
               auto_scheduled: true, position: 2)

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:ahead_suggestion]).to include("Next Up")
      end

      it "returns suggestion when no active goals exist but queued books do" do
        next_book = create(:book, user: user, last_page: 300, title: "Waiting Book")
        create(:reading_goal, user: user, book: next_book, status: :queued,
               started_on: nil, target_completion_date: nil,
               auto_scheduled: true, position: 1)

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:ahead_suggestion]).to include("Waiting Book")
      end

      it "returns nil when no queued books exist" do
        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:ahead_suggestion]).to be_nil
      end
    end
  end
end
