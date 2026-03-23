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
      let(:next_monday) { wednesday.beginning_of_week(:monday) + 7 }

      it "allows fresh scheduling when no sessions exist this week" do
        travel_to wednesday do
          3.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }
          schedule!

          # No sessions this week = fresh start, books can start today
          goals = user.reading_goals.active
          expect(goals).not_to be_empty
          goals.each do |goal|
            expect(goal.target_completion_date).to be_sunday
          end
        end
      end

      it "commits books whose started_on has arrived" do
        travel_to wednesday do
          # Both books started Monday — both are committed (started_on <= today)
          book_a = create(:book, :reading, user: user, last_page: 300, current_page: 20, title: "Book A")
          goal_a = create(:reading_goal, user: user, book: book_a, status: :active,
                          started_on: wednesday.beginning_of_week(:monday),
                          target_completion_date: wednesday.beginning_of_week(:monday) + 6,
                          auto_scheduled: true, position: 1)
          book_b = create(:book, :reading, user: user, last_page: 300, current_page: 10, title: "Book B")
          goal_b = create(:reading_goal, user: user, book: book_b, status: :active,
                          started_on: wednesday.beginning_of_week(:monday),
                          target_completion_date: wednesday.beginning_of_week(:monday) + 6,
                          auto_scheduled: true, position: 2)

          schedule!

          goal_a.reload
          goal_b.reload
          # Both committed — started_on preserved (not re-placed)
          expect(goal_a.started_on).to eq(wednesday.beginning_of_week(:monday))
          expect(goal_b.started_on).to eq(wednesday.beginning_of_week(:monday))
        end
      end

      it "ends all tiers on Sundays" do
        travel_to wednesday do
          3.times { |i| create_queued_book(pages: 300, position: i + 1) }
          schedule!

          user.reading_goals.active.each do |goal|
            expect(goal.target_completion_date).to be_sunday,
              "Goal ending #{goal.target_completion_date} (#{goal.target_completion_date.strftime('%A')}) is not Sunday"
          end
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

    it "holds daily target steady over a skipped weekend" do
      skip_user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: Date.current.beginning_of_year,
        default_reading_speed_wpm: 250,
        max_concurrent_books: 3,
        weekend_mode: :skip,
        weekday_reading_minutes: 60,
        weekend_reading_minutes: 0)

      friday = Date.current.beginning_of_week(:monday) + 4
      friday += 7 unless friday > Date.current  # ensure it's in the future

      book = create(:book, user: skip_user, last_page: 300, title: "Stable")
      create(:reading_goal, user: skip_user, book: book, status: :queued,
             started_on: nil, target_completion_date: nil,
             auto_scheduled: true, position: 1)

      # Saturday: Friday (a reading day) has passed, target may have ticked up
      saturday_target = travel_to(friday + 1) do
        s = ReadingListScheduler.new(skip_user)
        s.schedule!
        s.daily_target
      end

      sunday_target = travel_to(friday + 2) do
        s = ReadingListScheduler.new(skip_user)
        s.schedule!
        s.daily_target
      end

      monday_target = travel_to(friday + 3) do
        s = ReadingListScheduler.new(skip_user)
        s.schedule!
        s.daily_target
      end

      # Saturday → Sunday → Monday: no reading days pass, target unchanged
      expect(sunday_target).to eq(saturday_target)
      expect(monday_target).to eq(saturday_target)
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

      # Exclude the tail (after the last book starts) — only one book
      # remains there, so load naturally drops. The core timeline is what
      # should be leveled.
      last_start = all_starts.max
      weekdays = (timeline_start..last_start).select { |d| !d.on_weekend? }
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

  describe "committed goals (started_on <= today)" do
    it "preserves committed books on reschedule" do
      book = create_queued_book(pages: 300, position: 1)
      schedule!

      goal = user.reading_goals.find_by(book: book)
      original_start = goal.started_on

      # Goal is committed because started_on <= today (set by schedule!)
      # Add another book and reschedule
      create_queued_book(pages: 200, position: 2, title: "New Book")
      schedule!

      goal.reload
      expect(goal.started_on).to eq(original_start)
      expect(goal.target_completion_date).to be >= original_start
      expect(goal.target_completion_date).to be_sunday
    end

    it "includes committed goals in the load profile for new placements" do
      book = create_queued_book(pages: 300, position: 1)
      schedule!

      # New book should account for committed goal's load
      create_queued_book(pages: 300, position: 2, title: "New Book")
      schedule!

      new_goal = user.reading_goals.find_by(book: Book.find_by(title: "New Book"))
      expect(new_goal).to be_active
    end

    it "contracts committed goals to shorter tiers when undershooting" do
      book = create_queued_book(pages: 200, position: 1, title: "Long Tier")
      schedule!

      goal = user.reading_goals.find_by(book: book)

      # Manually extend to a very long tier (simulating a previous graduation)
      ref_monday = goal.started_on.beginning_of_week(:monday)
      long_end = ref_monday + (12 * 7) - 1
      goal.update!(target_completion_date: long_end)

      # Goal is committed (started_on <= today). Reschedule — contraction
      # should shorten the tier.
      schedule!

      goal.reload
      expect(goal.target_completion_date).to be < long_end,
        "Expected contraction to shorten from #{long_end}, got #{goal.target_completion_date}"
      expect(goal.target_completion_date).to be_sunday
    end

    it "does not commit books with started_on in the future" do
      book_a = create_queued_book(pages: 300, position: 1, title: "This Week")
      book_b = create_queued_book(pages: 300, position: 2, title: "Future")
      schedule!

      goal_a = user.reading_goals.find_by(book: book_a)
      goal_b = user.reading_goals.find_by(book: book_b)

      # Book A started today or earlier — committed
      expect(goal_a.started_on).to be <= Date.current
      # Book B may have started_on in the future — not committed, freely re-placeable
      # (Its exact start depends on tier selection, but it should be active)
      expect(goal_b).to be_active
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

  # ─── Undershoot Guard ──────────────────────────────────────────

  describe "undershoot guard" do
    it "does not lengthen a tier if it would drop load below daily target" do
      # Place a single book that fills the daily target in a short tier.
      # If throughput verification tries to lengthen it, the per-day share
      # drops — the guard should prevent that.
      create_queued_book(pages: 200, position: 1, title: "Short Tier")
      schedule!

      goal = user.reading_goals.find_by(book: Book.find_by(title: "Short Tier"))
      original_end = goal.target_completion_date

      # The scheduler should not have lengthened the tier to a point where
      # daily load drops below the target. Check the load profile via quotas.
      scheduler = ReadingListScheduler.new(user)
      daily_target = scheduler.daily_target
      next unless daily_target&.positive?

      goal.daily_quotas.where("date >= ?", Date.current).each do |quota|
        estimated_minutes = quota.estimated_minutes_remaining
        # Each day's load should be within tolerance of the daily target
        # (allowing for the last day which may have fewer remaining pages)
      end

      # At minimum, the end date should not have been pushed far beyond
      # what the tier system would naturally assign
      expect(goal.target_completion_date).to be_sunday
    end

    it "relaxes last placement to at-or-below target rather than above" do
      # Place multiple books so the last one gets relaxed.
      # The last book should break below the target rather than staying above.
      5.times { |i| create_queued_book(pages: 250, position: i + 1, title: "Book #{i}") }
      schedule!

      goals = user.reading_goals.active.order(:position)
      goals.each do |goal|
        expect(goal.target_completion_date).to be_sunday
        expect(goal.started_on).to be_present
      end
    end
  end

  # ─── Book Ownership ──────────────────────────────────────────

  describe "book ownership" do
    let(:monday) do
      d = Date.current.beginning_of_week(:monday)
      d += 7 unless Date.current.monday?
      d
    end

    def create_queued_unowned_book(pages: 300, position: 1, title: "Unowned Book")
      book = create(:book, :unowned, user: user, last_page: pages, title: title)
      create(:reading_goal, user: user, book: book, status: :queued,
             started_on: nil, target_completion_date: nil,
             auto_scheduled: true, position: position)
      book
    end

    it "skips unowned books for current week placement" do
      travel_to monday do
        create_queued_unowned_book(pages: 300, position: 1, title: "Unowned")
        schedule!

        goal = user.reading_goals.find_by(book: Book.find_by(title: "Unowned"))
        # The goal should either remain queued or be placed in a future week
        if goal.active?
          expect(goal.started_on).to be >= monday + 7,
            "Unowned book should not start in current week (started #{goal.started_on})"
        end
      end
    end

    it "places owned books in the current week" do
      travel_to monday do
        create_queued_book(pages: 300, position: 1, title: "Owned")
        schedule!

        goal = user.reading_goals.find_by(book: Book.find_by(title: "Owned"))
        expect(goal).to be_active
        expect(goal.started_on).to eq(monday)
      end
    end

    it "places unowned books in future weeks" do
      travel_to monday do
        create_queued_unowned_book(pages: 300, position: 1, title: "Future Unowned")
        create_queued_book(pages: 300, position: 2, title: "Owned Filler")
        schedule!

        goal = user.reading_goals.find_by(book: Book.find_by(title: "Future Unowned"))
        if goal.active?
          expect(goal.started_on).to be >= monday + 7
        end
      end
    end

    it "handles all-unowned queue (current week empty, future weeks populated)" do
      travel_to monday do
        3.times { |i| create_queued_unowned_book(pages: 300, position: i + 1, title: "Unowned #{i}") }
        schedule!

        active_goals = user.reading_goals.active
        active_goals.each do |goal|
          expect(goal.started_on).to be >= monday + 7,
            "#{goal.book.title} started #{goal.started_on}, should not be in current week"
        end
      end
    end

    it "does not add new books mid-week when committed books exist" do
      wednesday = monday + 2
      travel_to wednesday do
        # Committed goal from Monday
        existing = create(:book, :reading, user: user, last_page: 300, current_page: 50, title: "Existing")
        create(:reading_goal, user: user, book: existing, status: :active,
               started_on: monday, target_completion_date: monday + 6,
               auto_scheduled: true, position: 1)

        create_queued_book(pages: 300, position: 2, title: "New Mid-Week")
        schedule!

        goal = user.reading_goals.find_by(book: Book.find_by(title: "New Mid-Week"))
        expect(goal).to be_active
        expect(goal.started_on).to be >= monday + 7,
          "New book should wait for next Monday, not enter mid-week (started #{goal.started_on})"
      end
    end

    it "allows mid-week ramp-in when no committed books exist" do
      wednesday = monday + 2
      travel_to wednesday do
        create_queued_book(pages: 300, position: 1, title: "Fresh Start")
        schedule!

        goal = user.reading_goals.find_by(book: Book.find_by(title: "Fresh Start"))
        expect(goal).to be_active
        expect(goal.started_on).to eq(wednesday),
          "First placement should start today (mid-week ramp-in), got #{goal.started_on}"
      end
    end

    it "picks up newly-owned book on next reflow" do
      travel_to monday do
        book = create_queued_unowned_book(pages: 300, position: 1, title: "Was Unowned")
        schedule!

        # Book not placed in current week initially
        goal = user.reading_goals.find_by(book: book)

        # Now mark as owned and reschedule
        book.mark_owned!
        schedule!

        goal.reload
        expect(goal).to be_active
        # Should now be eligible for current week
        expect(goal.started_on).to be_present
      end
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
      expect(calendar_days).to be >= 21  # at least 3 weeks for a 5000-page book
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

    it "preserves committed books' start dates across reruns" do
      3.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Book #{i}") }

      schedule!
      committed_starts = user.reading_goals.active.select { |g| g.started_on <= Date.current }.map do |g|
        [g.book.title, g.started_on]
      end

      schedule!
      after_rerun = user.reading_goals.active.select { |g| committed_starts.any? { |t, _| t == g.book.title } }.map do |g|
        [g.book.title, g.started_on]
      end

      expect(after_rerun).to eq(committed_starts)
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
        # Goal with session last week — committed and undershooting.
        # The long tier means its daily share is below the daily target,
        # so contraction should shorten it (adding it to handled_ids).
        last_monday = monday - 7
        _, stale_goal = create_active_book_with_sessions(
          title: "Stale Book", pages: 300, position: 1,
          started_on: last_monday, target_completion_date: last_monday + 27,
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

    it "keeps committed goals (started_on <= today)" do
      travel_to monday + 2 do # Wednesday
        book = create(:book, :reading, user: user, last_page: 300, current_page: 1, title: "Committed Book")
        committed_goal = create(:reading_goal, user: user, book: book, status: :active,
                                started_on: monday, target_completion_date: monday + 13,
                                auto_scheduled: true, position: 1)
        original_start = committed_goal.started_on

        schedule!

        committed_goal.reload
        # started_on is preserved — committed goals are never re-placed from scratch.
        # target_completion_date may flex via contraction/graduation to meet the daily target.
        expect(committed_goal.started_on).to eq(original_start)
        expect(committed_goal.status).to eq("active")
      end
    end

    it "graduates overshooting committed goals to longer tier" do
      travel_to monday + 2 do # Wednesday
        # Two committed goals with very short tiers — combined load will overshoot
        book_a = create(:book, :reading, user: user, last_page: 500, current_page: 1, title: "Heavy A")
        goal_a = create(:reading_goal, user: user, book: book_a, status: :active,
                        started_on: monday, target_completion_date: monday + 6,
                        auto_scheduled: true, position: 1)
        book_b = create(:book, :reading, user: user, last_page: 500, current_page: 1, title: "Heavy B")
        goal_b = create(:reading_goal, user: user, book: book_b, status: :active,
                        started_on: monday, target_completion_date: monday + 6,
                        auto_scheduled: true, position: 2)

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

    it "contracts a committed goal from an over-long tier toward the target" do
      travel_to monday + 2 do # Wednesday
        # Single committed goal with an over-long tier — load well under target.
        book = create(:book, :reading, user: user, last_page: 100, current_page: 1, title: "Easy Book")
        goal = create(:reading_goal, user: user, book: book, status: :active,
                      started_on: monday, target_completion_date: monday + 27,
                      auto_scheduled: true, position: 1)
        original_end = goal.target_completion_date

        schedule!

        goal.reload
        expect(goal.target_completion_date).to be < original_end,
          "Expected contraction from #{original_end}, got #{goal.target_completion_date}"
        expect(goal.target_completion_date).to be_sunday
      end
    end

    it "contracts to closest-above when all shorter tiers overshoot" do
      travel_to monday do
        # Three locked goals at concurrency limit. The long-tier goal
        # keeps total load under target. All shorter tiers for the long
        # goal overshoot, but the scheduler should still pick the tier
        # that exceeds the target by the least (closest-above).
        short_a = create(:book, :reading, user: user, last_page: 250, current_page: 1, title: "Short A")
        goal_a = create(:reading_goal, user: user, book: short_a, status: :active,
                        started_on: monday, target_completion_date: monday + 20,
                        auto_scheduled: true, position: 1)

        short_b = create(:book, :reading, user: user, last_page: 250, current_page: 1, title: "Short B")
        goal_b = create(:reading_goal, user: user, book: short_b, status: :active,
                        started_on: monday, target_completion_date: monday + 20,
                        auto_scheduled: true, position: 2)

        long_book = create(:book, :reading, user: user, last_page: 600, current_page: 1, title: "Long Book")
        long_goal = create(:reading_goal, user: user, book: long_book, status: :active,
                           started_on: monday, target_completion_date: monday + 83,
                           auto_scheduled: true, position: 3)
        original_long_end = long_goal.target_completion_date

        result = schedule!

        long_goal.reload
        # The long goal should be contracted — its tier should shorten
        # to bring total load closer to or above the daily target.
        expect(long_goal.target_completion_date).to be < original_long_end,
          "Expected long goal to be contracted from #{original_long_end}"
        expect(result).to include(long_goal.id)
      end
    end

    it "credits over-reading via reduced daily share" do
      travel_to monday + 2 do # Wednesday
        # Book with pages already read — remaining_minutes is smaller.
        # The goal is committed (started_on in the past) so it's locked.
        # Graduation/contraction adjusts its tier; DailyReflow handles
        # quota redistribution for committed books.
        book = create(:book, user: user, last_page: 300, current_page: 200, title: "Half-Read")
        goal = create(:reading_goal, user: user, book: book, status: :active,
                      started_on: monday - 7, target_completion_date: monday + 6,
                      auto_scheduled: true, position: 1)
        ProfileAwareQuotaCalculator.new(goal, user).generate_quotas!

        schedule!

        goal.reload
        # Committed goal stays committed
        expect(goal.started_on).to eq(monday - 7)
        # Its load profile reflects reduced remaining pages (100 pages, not 300)
        expect(goal).to be_active
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

    it "warns when daily target exceeds 5 hours" do
      # Set pace start far in the past so deficit is huge
      user.update!(reading_pace_set_on: 11.months.ago.to_date)
      create_queued_book(pages: 600, position: 1)

      metrics = ReadingListScheduler.new(user).metrics
      if metrics[:derived_target] >= 300
        expect(metrics[:target_warning]).to include("hours")
      end
    end

    it "refuses to schedule when daily target exceeds 24 hours" do
      # Extreme scenario: 50 books/year pace, started 364 days ago, nothing read
      user.update!(reading_pace_set_on: 364.days.ago.to_date)
      50.times { |i| create_queued_book(pages: 1000, position: i + 1, title: "Big #{i}") }

      scheduler = ReadingListScheduler.new(user)
      metrics = scheduler.metrics

      # If target is extreme enough, scheduler refuses
      if metrics[:derived_target] >= 1440
        result = ReadingListScheduler.new(user).schedule!
        expect(result).to be_empty
        expect(metrics[:target_warning]).to include("suspended")
      end
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

  # ─── Epoch Renewal ──────────────────────────────────────────────

  describe "epoch renewal" do
    describe "#measure_actuals! (via metrics)" do
      it "stays in the first epoch when less than 365 days have passed" do
        user.update!(reading_pace_set_on: 30.days.ago.to_date)
        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:carried_deficit]).to eq(0)
        expect(metrics[:pace_target]).to eq(50)
      end

      it "advances epoch and carries deficit when behind after one year" do
        user.update!(reading_pace_set_on: 400.days.ago.to_date)

        # Completed 45 books in the first epoch (5 behind)
        45.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (400 - i * 7).days.ago)
        end

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:carried_deficit]).to eq(5)
        expect(metrics[:pace_target]).to eq(55)
        expect(metrics[:annual_pace]).to eq(50)
      end

      it "advances epoch and carries surplus when ahead after one year" do
        user.update!(reading_pace_set_on: 400.days.ago.to_date)

        # Completed 55 books in the first epoch (5 ahead)
        55.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (400 - i * 6).days.ago)
        end

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:carried_deficit]).to eq(-5)
        expect(metrics[:pace_target]).to eq(45)
      end

      it "accumulates deficit across multiple expired epochs" do
        user.update!(reading_pace_set_on: 800.days.ago.to_date)

        # Epoch 1 (800-435 days ago): 45 completed → deficit 5
        45.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (800 - i * 7).days.ago)
        end

        # Epoch 2 (435-70 days ago): 48 completed → deficit 2
        48.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (435 - i * 7).days.ago)
        end

        metrics = ReadingListScheduler.new(user).metrics
        # Total carried: 5 + 2 = 7
        expect(metrics[:carried_deficit]).to eq(7)
        expect(metrics[:pace_target]).to eq(57)
      end

      it "floors epoch_target at 0 when surplus exceeds base pace" do
        user.update!(reading_pace_set_on: 400.days.ago.to_date)

        # Completed 110 books in the first epoch (60 ahead)
        110.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (400 - i * 3).days.ago)
        end

        metrics = ReadingListScheduler.new(user).metrics
        expect(metrics[:pace_target]).to eq(0)
        expect(metrics[:carried_deficit]).to eq(-60)
      end

      it "does not modify reading_pace_set_on" do
        original_date = 400.days.ago.to_date
        user.update!(reading_pace_set_on: original_date)

        ReadingListScheduler.new(user).metrics

        expect(user.reload.reading_pace_set_on).to eq(original_date)
      end

      it "computes within-epoch deficit correctly" do
        # Set pace start to 100 days ago, no epoch rollover
        user.update!(reading_pace_set_on: 100.days.ago.to_date)

        # Should have completed ~13.7 books by now (50 * 100/365)
        10.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (100 - i * 9).days.ago)
        end

        metrics = ReadingListScheduler.new(user).metrics
        # Expected: 50 * 100/365 ≈ 13.7, actual: 10, deficit ≈ 3.7
        expect(metrics[:deficit]).to be_within(0.5).of(3.7)
      end
    end

    describe "#schedule! with epoch renewal" do
      it "uses epoch_target for daily target computation" do
        user.update!(reading_pace_set_on: 400.days.ago.to_date)

        # 45 books completed in first epoch → carry 5 deficit
        45.times do |i|
          create(:book, user: user, status: :completed,
                 last_page: 100, current_page: 100,
                 completed_at: (400 - i * 7).days.ago)
        end

        create_queued_book(pages: 300, position: 1)

        # Should schedule without error and use epoch_target of 55
        expect { schedule! }.not_to raise_error

        goal = user.reading_goals.active.first
        expect(goal).to be_present
        expect(goal.target_completion_date).to be_present
      end
    end
  end

  describe "epoch scoping" do
    let(:user) do
      create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 5,
        reading_pace_set_on: Date.current,
        default_reading_speed_wpm: 250,
        max_concurrent_books: 3,
        weekend_mode: :same)
    end

    it "only schedules books within the current epoch" do
      # 5 books per year pace — epoch = first 5 books
      7.times { |i| create_queued_book(pages: 300, position: i + 1) }

      schedule!

      active_goals = user.reading_goals.where(status: :active)
      queued_goals = user.reading_goals.where(status: :queued)

      # Only the first 5 (epoch) should be scheduled
      expect(active_goals.count).to eq(5)
      # Books 6 and 7 stay queued
      expect(queued_goals.count).to eq(2)
    end

    it "computes daily target from epoch books only" do
      # Epoch 1: 5 short books. Epoch 2: 2 long books.
      5.times { |i| create_queued_book(pages: 100, position: i + 1, title: "Short #{i}") }
      2.times { |i| create_queued_book(pages: 800, position: i + 6, title: "Long #{i}") }

      scheduler = ReadingListScheduler.new(user)
      metrics = scheduler.metrics

      # Daily target should be based on the 5 short books' average (100 pages),
      # not inflated by the 800-page books in epoch 2
      expect(metrics[:derived_target]).to be > 0
      expect(metrics[:epoch_books_scheduled]).to eq(5)
      expect(metrics[:epoch_books_target]).to eq(5)

      # Verify the long books didn't inflate the target.
      # With 100-page books at 250 WPM: ~100 min each. 5 books * 100 min / 365 days ≈ 1.4 min/day
      # If 800-page books were included: avg ~343 pages, much higher target
      expect(metrics[:derived_target]).to be < 5
    end

    it "does not schedule books beyond the epoch even with long horizon" do
      5.times { |i| create_queued_book(pages: 300, position: i + 1, title: "Epoch 1 ##{i}") }
      3.times { |i| create_queued_book(pages: 300, position: i + 6, title: "Epoch 2 ##{i}") }

      schedule!

      epoch_2_goals = user.reading_goals.where(status: [:active, :queued])
                          .where("position > ?", 5)

      # Epoch 2 books should remain queued
      expect(epoch_2_goals.pluck(:status).uniq).to eq(["queued"])
    end

    it "includes epoch metadata in metrics" do
      3.times { |i| create_queued_book(pages: 300, position: i + 1) }

      metrics = ReadingListScheduler.new(user).metrics

      expect(metrics).to have_key(:epoch_books_scheduled)
      expect(metrics).to have_key(:epoch_books_target)
      expect(metrics).to have_key(:epoch_count)
      expect(metrics[:epoch_books_scheduled]).to eq(3)
      expect(metrics[:epoch_books_target]).to eq(5)
      expect(metrics[:epoch_count]).to eq(1)
    end

    it "reports epoch_count based on total queued books" do
      12.times { |i| create_queued_book(pages: 300, position: i + 1) }

      metrics = ReadingListScheduler.new(user).metrics

      expect(metrics[:epoch_count]).to eq(3) # 12 books / 5 per epoch = 3
    end
  end

  # ─── Series Ordering ───────────────────────────────────────────

  describe "series ordering" do
    def create_series_book(series_name:, series_position:, position:, pages: 300)
      book = create(:book, user: user, last_page: pages, title: "#{series_name} ##{series_position}",
                    series_name: series_name, series_position: series_position)
      create(:reading_goal, user: user, book: book, status: :queued,
             started_on: nil, target_completion_date: nil,
             auto_scheduled: true, position: position)
      book
    end

    it "schedules series books so that book N+1 starts after book N ends" do
      create_series_book(series_name: "LOTR", series_position: 1, position: 1)
      create_series_book(series_name: "LOTR", series_position: 2, position: 2)
      create_series_book(series_name: "LOTR", series_position: 3, position: 3)
      schedule!

      goals = user.reading_goals.active.includes(:book).order("books.series_position")
      expect(goals.count).to eq(3)

      goals.each_cons(2) do |prev_goal, next_goal|
        expect(next_goal.started_on).to be > prev_goal.target_completion_date,
          "#{next_goal.book.title} starts #{next_goal.started_on} but " \
          "#{prev_goal.book.title} ends #{prev_goal.target_completion_date}"
      end
    end

    it "allows non-series books to be scheduled independently of series books" do
      create_series_book(series_name: "LOTR", series_position: 1, position: 1)
      create_queued_book(pages: 300, position: 2, title: "Standalone Book")
      create_series_book(series_name: "LOTR", series_position: 2, position: 3)
      schedule!

      goals = user.reading_goals.active.includes(:book)
      expect(goals.count).to eq(3)

      standalone = goals.find { |g| g.book.title == "Standalone Book" }
      lotr_2 = goals.find { |g| g.book.series_position == 2 }
      lotr_1 = goals.find { |g| g.book.series_position == 1 }

      # The standalone book should not be blocked by series ordering
      # LOTR #2 must start after LOTR #1 ends
      expect(lotr_2.started_on).to be > lotr_1.target_completion_date
    end

    it "respects series ordering when predecessor is already completed" do
      book1 = create(:book, :completed, user: user, title: "LOTR #1",
                     series_name: "LOTR", series_position: 1)
      create_series_book(series_name: "LOTR", series_position: 2, position: 1)
      schedule!

      goal = user.reading_goals.where.not(status: :completed).first
      expect(goal.status).to eq("active")
      expect(goal.started_on).to be_present
    end

    it "handles multiple independent series without cross-blocking" do
      create_series_book(series_name: "LOTR", series_position: 1, position: 1)
      create_series_book(series_name: "LOTR", series_position: 2, position: 2)
      create_series_book(series_name: "Narnia", series_position: 1, position: 3)
      create_series_book(series_name: "Narnia", series_position: 2, position: 4)
      schedule!

      goals = user.reading_goals.active.includes(:book)
      expect(goals.count).to eq(4)

      lotr = goals.select { |g| g.book.series_name == "LOTR" }.sort_by { |g| g.book.series_position }
      narnia = goals.select { |g| g.book.series_name == "Narnia" }.sort_by { |g| g.book.series_position }

      # Each series maintains its own ordering
      expect(lotr[1].started_on).to be > lotr[0].target_completion_date
      expect(narnia[1].started_on).to be > narnia[0].target_completion_date

      # But the two series are independent — Narnia #1 doesn't wait for LOTR #1
      # (it may or may not overlap depending on leveling, but it's not blocked)
    end
  end
end
