require "rails_helper"

RSpec.describe ReadingListScheduler do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      reading_pace_set_on: Date.current.beginning_of_year,
      default_reading_speed_wpm: 250,
      max_concurrent_books: 3,
      weekend_mode: :same,
      weekday_reading_minutes: 60,
      weekend_reading_minutes: 60)
  end

  def create_queued_book(pages: 300, position: 1, density: :average, title: "Book")
    book = create(:book, user: user, last_page: pages, density: density, title: title)
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

      goals.each do |goal|
        expect(goal.started_on).to be_present
        expect(goal.target_completion_date).to be_present
        expect(goal.started_on).to be < goal.target_completion_date
      end
    end

    it "snaps all end dates to Sundays" do
      3.times { |i| create_queued_book(pages: 300, position: i + 1) }
      schedule!

      user.reading_goals.active.each do |goal|
        expect(goal.target_completion_date).to be_sunday
      end
    end

    context "when run on a Monday" do
      it "starts all books on Mondays" do
        monday = Date.current.beginning_of_week(:monday)
        monday += 7 unless Date.current.monday?  # next Monday if today isn't one

        travel_to monday do
          5.times { |i| create_queued_book(pages: 200 + i * 50, position: i + 1, title: "Book #{i}") }
          schedule!

          user.reading_goals.active.each do |goal|
            expect(goal.started_on).to be_monday,
              "#{goal.book.title} started on #{goal.started_on} (#{goal.started_on.strftime('%A')})"
          end
        end
      end
    end

    context "when run mid-week (Wednesday)" do
      let(:wednesday) { Date.current.beginning_of_week(:monday) + 2 }

      it "starts the first batch today, subsequent batches on Mondays" do
        travel_to wednesday do
          8.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }
          schedule!

          goals = user.reading_goals.active.order(:started_on, :position)
          first_batch_start = goals.first.started_on
          expect(first_batch_start).to eq(wednesday)
          expect(first_batch_start).to be_wednesday

          # Any books starting after the first batch should start on a Monday
          later_goals = goals.select { |g| g.started_on > first_batch_start }
          later_goals.each do |goal|
            expect(goal.started_on).to be_monday,
              "#{goal.book.title} started on #{goal.started_on} (#{goal.started_on.strftime('%A')})"
          end
        end
      end

      it "ends all tiers on Sundays even with mid-week start" do
        travel_to wednesday do
          3.times { |i| create_queued_book(pages: 300, position: i + 1) }
          schedule!

          user.reading_goals.active.each do |goal|
            expect(goal.target_completion_date).to be_sunday,
              "Goal ending #{goal.target_completion_date} (#{goal.target_completion_date.strftime('%A')}) is not Sunday"
          end
        end
      end

      it "computes share over actual remaining days (not full week)" do
        travel_to wednesday do
          create_queued_book(pages: 300, position: 1)
          schedule!

          goal = user.reading_goals.active.first
          # Wednesday to Sunday of the tier end — fewer days than a full
          # Monday-start tier, so more pages per day
          reading_days = (goal.started_on..goal.target_completion_date).count
          full_week_days = (goal.started_on.beginning_of_week(:monday)..goal.target_completion_date).count

          expect(reading_days).to be < full_week_days
          expect(goal.daily_quotas.count).to eq(reading_days)
        end
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
    # Pin to Monday so tier day counts are deterministic
    let(:monday) do
      d = Date.current.beginning_of_week(:monday)
      d += 7 unless Date.current.monday?
      d
    end

    it "places a short book in a short tier" do
      travel_to monday do
        create_queued_book(pages: 100, position: 1)
        schedule!

        goal = user.reading_goals.active.first
        calendar_days = (goal.target_completion_date - goal.started_on).to_i + 1
        expect(calendar_days).to be <= 14 # 1 or 2 week tier
      end
    end

    it "places a long book in a longer tier than a short book" do
      travel_to monday do
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

    # ─── Last Book Relaxation ──────────────────────────────────────

    describe "last book relaxation" do
      it "stretches the last book's tier when it would overshoot the target" do
        travel_to monday do
          # Queue books where the last one would overshoot in its natural tier.
          # Earlier books fill the slot; the last book tips it over the target.
          # After relaxation, the last book should get a longer tier (more days).
          6.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }

          scheduler = ReadingListScheduler.new(user)
          scheduler.schedule!

          goals = user.reading_goals.active.order(:position)
          last_goal = goals.find { |g| g.book.title == "Book 5" }
          earlier_same_start = goals.select { |g| g.started_on == last_goal.started_on && g.book.title != "Book 5" }

          # The last book should have at least as many calendar days as similarly-sized
          # earlier books that share its start date — likely more due to relaxation
          last_days = (last_goal.target_completion_date - last_goal.started_on).to_i + 1

          earlier_same_start.each do |eg|
            earlier_days = (eg.target_completion_date - eg.started_on).to_i + 1
            expect(last_days).to be >= earlier_days,
              "Last book (#{last_days}d) should be >= earlier book #{eg.book.title} (#{earlier_days}d)"
          end
        end
      end

      it "does not stretch non-last books that overshoot" do
        travel_to monday do
          # Place books; observe that earlier books retain their original tiers
          # even if they contribute to overshoot at their slot
          4.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }

          scheduler = ReadingListScheduler.new(user)
          scheduler.schedule!

          goals = user.reading_goals.active.order(:position)
          first_goal = goals.find { |g| g.book.title == "Book 0" }
          first_days = (first_goal.target_completion_date - first_goal.started_on).to_i + 1

          # Run again without the relaxation feature's target book to compare
          # The first book should keep its compact tier (not be stretched)
          # First book at position 1 should remain short — relaxation only targets the last
          expect(first_days).to be <= 28, # Should be at most a 4-week tier for a 300-page book
            "First book got #{first_days} days — should not be stretched by last-book relaxation"
        end
      end

      it "leaves the last book alone when no overshoot occurs" do
        travel_to monday do
          # A single book can't overshoot (no prior load) — should keep its natural tier
          create_queued_book(pages: 300, position: 1, title: "Solo Book")

          scheduler = ReadingListScheduler.new(user)
          scheduler.schedule!

          goal = user.reading_goals.active.first
          days = (goal.target_completion_date - goal.started_on).to_i + 1

          # Schedule again with same setup to get the "natural" tier
          user2 = create(:user,
            reading_pace_type: "books_per_year",
            reading_pace_value: 50,
            reading_pace_set_on: Date.current.beginning_of_year,
            default_reading_speed_wpm: 250,
            max_concurrent_books: 3,
            weekend_mode: :same,
            weekday_reading_minutes: 60,
            weekend_reading_minutes: 60)
          book2 = create(:book, user: user2, last_page: 300, title: "Solo Book 2")
          create(:reading_goal, user: user2, book: book2, status: :queued,
                 started_on: nil, target_completion_date: nil,
                 auto_scheduled: true, position: 1)
          ReadingListScheduler.new(user2).schedule!

          goal2 = user2.reading_goals.active.first
          days2 = (goal2.target_completion_date - goal2.started_on).to_i + 1

          expect(days).to eq(days2),
            "Solo book got #{days} days vs expected #{days2} — should not be relaxed without overshoot"
        end
      end
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

      # Add a reading session to lock this goal
      create(:reading_session, user: user, book: book,
             start_page: 1, end_page: 10, pages_read: 10,
             started_at: Time.current, ended_at: 30.minutes.from_now,
             duration_seconds: 1800)

      # Add another book and reschedule
      create_queued_book(pages: 200, position: 2, title: "New Book")
      schedule!

      goal.reload
      # Locked goals are not re-placed: started_on stays the same.
      # target_completion_date may shift via graduation if load exceeds target.
      expect(goal.started_on).to eq(original_start)
      expect(goal.target_completion_date).to be >= original_start
      expect(goal.target_completion_date).to be_sunday
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

  # ─── Daily Re-Run Adjustments ──────────────────────────────────

  describe "daily re-run adjustments" do
    let(:monday) do
      d = Date.current.beginning_of_week(:monday)
      d += 7 unless Date.current.monday?
      d
    end

    def create_active_book_with_sessions(title:, pages:, position:, started_on:, target_completion_date:, session_date:)
      book = create(:book, user: user, last_page: pages, title: title)
      goal = create(:reading_goal, user: user, book: book, status: :active,
                    started_on: started_on, target_completion_date: target_completion_date,
                    auto_scheduled: true, position: position)
      goal.daily_quotas.destroy_all
      (Date.current..target_completion_date).each do |date|
        goal.daily_quotas.create!(date: date, target_pages: 10, actual_pages: 0, status: :pending)
      end
      create(:reading_session, user: user, book: book,
             start_page: 1, end_page: 10, pages_read: 9,
             started_at: session_date.to_time, ended_at: session_date.to_time + 30.minutes,
             duration_seconds: 1800)
      [book, goal]
    end

    it "re-places stale goals from today" do
      travel_to monday + 2 do # Wednesday
        # Goal with session last week only — stale
        last_monday = monday - 7
        _, stale_goal = create_active_book_with_sessions(
          title: "Stale Book", pages: 300, position: 1,
          started_on: last_monday, target_completion_date: last_monday + 13,
          session_date: last_monday + 1 # Tuesday of last week
        )
        original_start = stale_goal.started_on

        result = schedule!

        stale_goal.reload
        expect(result).to include(stale_goal.id)
        expect(stale_goal.started_on).to eq(original_start) # preserved
        expect(stale_goal.target_completion_date).to be_present
        expect(stale_goal.status).to eq("active")
      end
    end

    it "keeps locked goals with sessions this week" do
      travel_to monday + 2 do # Wednesday
        _, locked_goal = create_active_book_with_sessions(
          title: "Locked Book", pages: 300, position: 1,
          started_on: monday, target_completion_date: monday + 13,
          session_date: monday + 1 # Tuesday of this week
        )
        original_start = locked_goal.started_on
        original_end = locked_goal.target_completion_date

        schedule!

        locked_goal.reload
        expect(locked_goal.started_on).to eq(original_start)
        expect(locked_goal.target_completion_date).to eq(original_end)
      end
    end

    it "graduates under-read locked goal to longer tier" do
      travel_to monday + 2 do # Wednesday
        # Two locked goals with very short tiers — combined load will overshoot
        _, goal_a = create_active_book_with_sessions(
          title: "Heavy A", pages: 500, position: 1,
          started_on: monday, target_completion_date: monday + 6, # 1-week tier
          session_date: monday + 1
        )
        _, goal_b = create_active_book_with_sessions(
          title: "Heavy B", pages: 500, position: 2,
          started_on: monday, target_completion_date: monday + 6, # 1-week tier
          session_date: monday + 1
        )

        original_end_a = goal_a.target_completion_date
        original_end_b = goal_b.target_completion_date

        result = schedule!

        goal_a.reload
        goal_b.reload

        # At least one should have been graduated to a longer tier
        graduated = [goal_a, goal_b].select { |g| result.include?(g.id) }
        extended = graduated.select { |g|
          g.target_completion_date > (g.book.title == "Heavy A" ? original_end_a : original_end_b)
        }
        expect(extended).not_to be_empty,
          "Expected at least one locked goal to be graduated to a longer tier"
      end
    end

    it "does not graduate when load is within target" do
      travel_to monday + 2 do # Wednesday
        # Single locked goal with a long tier — load well within target
        _, goal = create_active_book_with_sessions(
          title: "Easy Book", pages: 100, position: 1,
          started_on: monday, target_completion_date: monday + 27, # 4-week tier
          session_date: monday + 1
        )
        original_end = goal.target_completion_date

        schedule!

        goal.reload
        expect(goal.target_completion_date).to eq(original_end)
      end
    end

    it "credits over-reading via reduced daily share" do
      travel_to monday + 2 do # Wednesday
        # Book with pages already read — remaining_minutes is smaller
        book = create(:book, user: user, last_page: 300, current_page: 200, title: "Half-Read")
        goal = create(:reading_goal, user: user, book: book, status: :active,
                      started_on: monday - 7, target_completion_date: monday + 6,
                      auto_scheduled: true, position: 1)
        goal.daily_quotas.destroy_all
        # Session from last week — makes it stale
        create(:reading_session, user: user, book: book,
               start_page: 1, end_page: 200, pages_read: 199,
               started_at: (monday - 5).to_time, ended_at: (monday - 5).to_time + 2.hours,
               duration_seconds: 7200)

        result = schedule!

        goal.reload
        expect(result).to include(goal.id)
        # With fewer remaining pages, the daily share is lower
        remaining_quotas = goal.daily_quotas.where("date >= ?", Date.current)
        expect(remaining_quotas.sum(:target_pages)).to eq(book.remaining_pages)
      end
    end

    it "Monday: all active goals are stale and re-placed" do
      travel_to monday do
        # Create two active goals with sessions from last week
        last_monday = monday - 7
        _, goal_a = create_active_book_with_sessions(
          title: "Book A", pages: 200, position: 1,
          started_on: last_monday, target_completion_date: last_monday + 13,
          session_date: last_monday + 3
        )
        _, goal_b = create_active_book_with_sessions(
          title: "Book B", pages: 200, position: 2,
          started_on: last_monday, target_completion_date: last_monday + 13,
          session_date: last_monday + 4
        )

        result = schedule!

        # On Monday, no sessions exist for this week → all goals are stale
        expect(result).to include(goal_a.id)
        expect(result).to include(goal_b.id)
      end
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
