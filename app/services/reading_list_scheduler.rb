class ReadingListScheduler
  TIERS = [:week, :two_weeks, :three_weeks, :four_weeks, :six_weeks,
           :twelve_weeks, :twenty_six_weeks, :fifty_two_weeks].freeze
  TIER_WEEKS = {
    week: 1, two_weeks: 2, three_weeks: 3, four_weeks: 4, six_weeks: 6,
    twelve_weeks: 12, twenty_six_weeks: 26, fifty_two_weeks: 52
  }.freeze
  MAX_ADJUSTMENT_ITERATIONS = 5
  PLACEMENT_HORIZON_WEEKS = 104
  CEILING_TOLERANCE = 15  # minutes above target before penalizing overshoot
  MIN_DAILY_SHARE = 5     # minutes — don't flatten a book below this per day

  attr_reader :daily_target, :deficit

  def initialize(user)
    @user = user
  end

  def metrics
    return default_metrics unless throughput_pace?

    measure_actuals!
    daily_target = compute_daily_target
    target = annual_pace.round

    pace_window_end = @pace_start + 365
    scheduled_completions = @user.reading_goals
      .where(status: [:active, :queued])
      .where.not(target_completion_date: nil)
      .where("target_completion_date <= ?", pace_window_end)
      .count
    projected = @actual_completed + scheduled_completions

    queued_count = @user.reading_goals.where(status: :queued, auto_scheduled: true).count

    {
      pace_status: pace_status_label(target),
      deficit: @deficit.round(1),
      derived_target: effective_daily_target(daily_target).round,
      projected_completions: projected,
      pace_target: target,
      queue_depth: queued_count,
      queue_warning: queue_warning(queued_count, target, projected),
      concurrency_hint: concurrency_hint(daily_target, target),
      ahead_suggestion: ahead_suggestion
    }
  end

  def schedule!
    return Set.new unless throughput_pace?

    # Phase 1: Measure actuals
    measure_actuals!

    # Phase 2: Compute derived daily target
    @daily_target = compute_daily_target
    return Set.new if @daily_target <= 0
    compute_weekend_targets

    # Phase 3: Slot-by-slot bin filling (first slot may be mid-week)
    @load_profile = Hash.new(0.0)
    @concurrent_count = Hash.new(0)
    @timeline_end = nil
    @graduated_ids = Set.new

    locked_goals.each { |goal| add_goal_to_profiles(goal) }

    # Phase 3a: Graduate under-read locked goals to longer tiers
    adjust_locked_goals!

    # Phase 3b: Place stale + queued goals
    @placements = fill_placements(gather_schedulable_goals)

    # Phase 4: Verify throughput
    verify_throughput!

    # Phase 5: Generate quotas
    handled_ids = Set.new(@graduated_ids)
    @placements.each do |entry|
      goal = entry[:goal]
      if @stale_goal_ids.include?(goal.id)
        regenerate_quotas_from_today!(goal)
      else
        generate_quotas_for!(goal)
      end
      handled_ids << goal.id
    end

    handled_ids
  end

  private

  # ─── Phase 1 ────────────────────────────────────────────────────

  def measure_actuals!
    @pace_start = @user.reading_pace_set_on || Date.current.beginning_of_year
    @days_elapsed = [(Date.current - @pace_start).to_i, 1].max
    @days_remaining = [365 - (Date.current - @pace_start).to_i, 1].max
    @actual_completed = count_completed_since(@pace_start)
    @deficit = (annual_pace * @days_elapsed / 365.0) - @actual_completed
  end

  def count_completed_since(date)
    @user.books
         .where(status: :completed)
         .where("completed_at >= ?", date.beginning_of_day)
         .count
  end

  # ─── Phase 2 ────────────────────────────────────────────────────

  def compute_daily_target
    books_remaining = [annual_pace - @actual_completed, 0].max
    return 0 if books_remaining <= 0

    window = build_pace_window([annual_pace.round, 1].max)
    return 0 if window.empty?

    avg_minutes = window.sum { |book| full_book_minutes(book) }.to_f / window.size
    (books_remaining * avg_minutes) / @days_remaining
  end

  def build_pace_window(window_size)
    list_books = @user.reading_goals
                      .where(auto_scheduled: true)
                      .where.not(position: nil)
                      .where(status: [:queued, :active])
                      .includes(:book)
                      .order(:position)
                      .limit(window_size)
                      .map(&:book)

    return list_books if list_books.size >= window_size

    remaining_slots = window_size - list_books.size
    exclude_ids = list_books.map(&:id)
    completed = @user.books
                     .where(status: :completed)
                     .where.not(id: exclude_ids)
                     .order(completed_at: :desc)
                     .limit(remaining_slots)
                     .to_a

    list_books + completed
  end

  def full_book_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.density_modifier)
    return 60 if wpm.zero?
    (book.total_words.to_f / wpm).ceil
  end

  def compute_weekend_targets
    weekly_total = @daily_target * 7
    if @user.skip?
      @weekday_target = weekly_total / 5.0
      @weekend_target = 0.0
    else
      @weekday_target = @weekend_target = weekly_total / 7.0
    end
  end

  def target_for_date(date)
    date.on_weekend? ? @weekend_target : @weekday_target
  end

  # ─── Phase 3: Slot-by-Slot Bin Filling ─────────────────────────
  #
  # The first slot starts today (mid-week ramp-in); subsequent slots
  # start on Mondays. Tier end dates always land on Sundays.

  def fill_placements(goals)
    return [] if goals.empty?

    share_index = build_share_index(goals)
    unscheduled = goals.map(&:id).to_set
    placements = []

    each_placement_start do |slot_start|
      break if unscheduled.empty?

      # Skip if spillover from prior multi-week placements already fills this slot
      next if slot_at_or_above_target?(slot_start)

      # Find the best combination of books to start at this slot
      combo = best_combination_for(share_index, goals, unscheduled, slot_start)
      next if combo.empty?

      combo.each do |entry|
        record_placement!(placements, entry[:goal], entry[:placement], entry[:book_minutes])
        unscheduled.delete(entry[:goal].id)
      end
    end

    # Stretch the last book if it caused overshoot
    relax_last_placement!(placements, goals)

    # Fallback: any books still unscheduled get default placement
    goals.each do |goal|
      next unless unscheduled.include?(goal.id)
      book_minutes = estimate_remaining_minutes(goal.book)
      placement = default_placement(book_minutes)
      record_placement!(placements, goal, placement, book_minutes)
      unscheduled.delete(goal.id)
    end

    placements
  end

  def build_share_index(goals)
    index = {}
    goals.each do |goal|
      book_minutes = estimate_remaining_minutes(goal.book)
      index[goal.id] = { goal: goal, book_minutes: book_minutes }
    end
    index
  end

  def compute_share_for(book_minutes, slot_start, tier)
    end_date = calendar_end(slot_start, tier)
    share = compute_weekday_share(book_minutes, slot_start, end_date)
    return nil if share <= 0
    { start: slot_start, end: end_date, share: share, tier: tier }
  end

  def slot_at_or_above_target?(slot_start)
    target = target_for_date(slot_start)
    return true if target <= 0
    @load_profile[slot_start] >= target
  end

  # Find the combination of (anchor + 0..N companions) × tiers that
  # overshoots the daily target by the least. The anchor is the next
  # unscheduled book in queue order. If no combination reaches the
  # target, pick the one that gets closest.
  def best_combination_for(share_index, goals, unscheduled, slot_start)
    target = target_for_date(slot_start)
    current_load = @load_profile[slot_start]
    open_slots = available_concurrency_slots(slot_start)
    return [] if open_slots <= 0

    # Build candidate placements: each unscheduled book × each tier
    candidates = build_candidates(share_index, goals, unscheduled, slot_start)
    return [] if candidates.empty?

    # The anchor is the first unscheduled book in queue order
    anchor_id = goals.find { |g| unscheduled.include?(g.id) }&.id
    return [] unless anchor_id

    anchor_options = candidates.select { |c| c[:goal_id] == anchor_id }
    return [] if anchor_options.empty?

    companion_options = candidates.reject { |c| c[:goal_id] == anchor_id }
    max_companions = [open_slots - 1, companion_options.size].min

    best_combo = nil
    best_score = nil  # [over_target?, distance] — prefer over-target, then min distance

    # Try each tier for the anchor
    anchor_options.each do |anchor|
      # Anchor alone
      evaluate_combination([anchor], current_load, target, best_score) do |score|
        best_score = score
        best_combo = [anchor]
      end

      next if max_companions <= 0

      # Anchor + 1 companion
      companion_options.each do |c1|
        next if dates_overlap_exceeds_slots?(anchor, c1, open_slots)

        evaluate_combination([anchor, c1], current_load, target, best_score) do |score|
          best_score = score
          best_combo = [anchor, c1]
        end

        next if max_companions <= 1

        # Anchor + 2 companions
        companion_options.each do |c2|
          next if c2[:goal_id] <= c1[:goal_id]  # avoid duplicate pairs
          next if c2[:goal_id] == c1[:goal_id]   # same book can't appear twice
          next if dates_overlap_exceeds_slots?(anchor, c1, c2, open_slots)

          evaluate_combination([anchor, c1, c2], current_load, target, best_score) do |score|
            best_score = score
            best_combo = [anchor, c1, c2]
          end
        end
      end
    end

    return [] unless best_combo

    best_combo.map do |c|
      { goal: share_index[c[:goal_id]][:goal],
        placement: c[:placement],
        book_minutes: c[:book_minutes] }
    end
  end

  def build_candidates(share_index, goals, unscheduled, slot_start)
    candidates = []
    goals.each do |goal|
      next unless unscheduled.include?(goal.id)
      entry = share_index[goal.id]

      TIERS.each do |tier|
        placement = compute_share_for(entry[:book_minutes], slot_start, tier)
        next unless placement
        next unless fits_concurrency?(placement[:start], placement[:end])

        slot_share = share_for_date(placement[:share], slot_start)
        next if slot_share < MIN_DAILY_SHARE

        candidates << {
          goal_id: goal.id,
          placement: placement,
          book_minutes: entry[:book_minutes],
          slot_share: slot_share
        }
      end
    end
    candidates
  end

  # Score: [priority_bucket, overshoot, max_tier_weeks, combo_size]
  #
  # Two-bucket scoring:
  #   Bucket 0: "close" — at/above target OR just under (within CEILING_TOLERANCE)
  #   Bucket 1: "far under" — more than CEILING_TOLERANCE below target
  #
  # Within each bucket, blend distance-from-target with schedule compactness.
  # Adding max_tier (weeks) to gap.abs (minutes) penalizes long tiers that
  # create extended low-load tails, while naturally preferring close-to-target
  # combos when the gap is large (short tiers for big books overshoot hugely).
  def evaluate_combination(combo, current_load, target, current_best)
    total_share = combo.sum { |c| c[:slot_share] }
    projected = current_load + total_share
    gap = projected - target

    bucket = gap >= -CEILING_TOLERANCE ? 0 : 1

    max_tier = combo.map { |c| TIER_WEEKS[c[:placement][:tier]] }.max

    score = [bucket, gap.abs + max_tier, combo.size]

    if current_best.nil? || (score <=> current_best) < 0
      yield score
    end
  end

  def available_concurrency_slots(slot_start)
    limit = effective_concurrency_limit
    return TIERS.size unless limit  # effectively unlimited
    [limit - @concurrent_count[slot_start], 0].max
  end

  # Check that placing these candidates together doesn't exceed concurrency
  # on any reading day they share. Quick check: the worst case is on the
  # slot start (all start the same day), plus we check individual placements.
  def dates_overlap_exceeds_slots?(*candidates, open_slots)
    return false if open_slots >= candidates.size
    candidates.size > open_slots
  end

  def fits_concurrency?(start_date, end_date)
    limit = effective_concurrency_limit
    return true unless limit
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      return false if @concurrent_count[date] >= limit
    end
    true
  end

  def record_placement!(placements, goal, placement, book_minutes)
    apply_placement!(goal, placement)
    add_range_to_profiles(placement[:start], placement[:end], placement[:share])
    placements << { goal: goal, placement: placement, tier: placement[:tier], book_minutes: book_minutes }
  end

  # After all books are placed, check whether the last book in queue order
  # pushed its slot over the daily target. If so, promote it to progressively
  # longer tiers until the overshoot is resolved or tiers are exhausted.
  # This only affects the final book — earlier books benefit from subsequent
  # placements filling remaining capacity, but the last book has nothing after it.
  def relax_last_placement!(placements, goals)
    return if placements.empty? || goals.empty?

    last_goal = goals.last
    entry = placements.find { |p| p[:goal].id == last_goal.id }
    return unless entry

    slot_start = entry[:placement][:start]
    target = target_for_date(slot_start)
    return if target <= 0
    return if @load_profile[slot_start] <= target

    current_tier_idx = TIERS.index(entry[:tier])
    return if current_tier_idx.nil?

    ((current_tier_idx + 1)...TIERS.size).each do |idx|
      longer_tier = TIERS[idx]
      new_end = calendar_end(slot_start, longer_tier)
      new_share = compute_weekday_share(entry[:book_minutes], slot_start, new_end)
      next if new_share <= 0

      # Remove old range, check concurrency, apply new range
      old_placement = entry[:placement]
      remove_range_from_profiles(old_placement[:start], old_placement[:end], old_placement[:share])

      unless fits_concurrency?(new_end > old_placement[:end] ? (old_placement[:end] + 1) : slot_start, new_end)
        add_range_to_profiles(old_placement[:start], old_placement[:end], old_placement[:share])
        next
      end

      new_placement = { start: slot_start, end: new_end, share: new_share, tier: longer_tier }
      add_range_to_profiles(slot_start, new_end, new_share)

      entry[:goal].update!(target_completion_date: new_end)
      entry[:tier] = longer_tier
      entry[:placement] = new_placement

      break if @load_profile[slot_start] <= target
    end
  end

  def compute_weekday_share(book_minutes, start_date, end_date)
    reading_days = count_reading_days(start_date, end_date)
    reading_days > 0 ? book_minutes.to_f / reading_days : 0
  end

  def share_for_date(share, _date)
    share
  end

  # Yields today first (mid-week ramp-in), then subsequent Mondays.
  # When today IS Monday, yields today and then Monday+7, Monday+14, etc.
  def each_placement_start
    start = Date.current
    unless start.monday?
      yield start
      start = start.beginning_of_week(:monday) + 7
    end
    PLACEMENT_HORIZON_WEEKS.times do
      yield start
      start += 7
    end
  end

  def apply_placement!(goal, placement)
    attrs = { target_completion_date: placement[:end], status: :active }
    # Preserve started_on for stale re-placements (already active goals)
    attrs[:started_on] = placement[:start] unless goal.active?
    goal.update!(attrs)
  end

  def add_goal_to_profiles(goal)
    return unless goal.started_on && goal.target_completion_date
    start = [goal.started_on, Date.current].max
    book_minutes = estimate_remaining_minutes(goal.book)
    daily_share = compute_weekday_share(book_minutes, start, goal.target_completion_date)
    return if daily_share <= 0
    add_range_to_profiles(start, goal.target_completion_date, daily_share)
  end

  def add_range_to_profiles(start_date, end_date, daily_share)
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      @load_profile[date] += share_for_date(daily_share, date)
      @concurrent_count[date] += 1
    end
    @timeline_end = [@timeline_end, end_date].compact.max if @timeline_end != false
  end

  def remove_range_from_profiles(start_date, end_date, daily_share)
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      @load_profile[date] -= share_for_date(daily_share, date)
      @concurrent_count[date] -= 1
    end
  end

  def default_placement(book_minutes)
    start = Date.current
    tier = TIERS.last
    end_date = calendar_end(start, tier)
    share = compute_weekday_share(book_minutes, start, end_date)
    { start: start, end: end_date, share: share, tier: tier }
  end

  # ─── Phase 3a: Locked Goal Graduation ──────────────────────────
  #
  # When locked goals' combined load overshoots the daily target in the
  # near term, graduate the heaviest one to a longer tier. This prevents
  # spikes from under-reading without waiting for the goal to become stale.

  def adjust_locked_goals!
    MAX_ADJUSTMENT_ITERATIONS.times do
      overshooting = (Date.current..(Date.current + 6)).any? do |date|
        next false unless reading_day?(date)
        target = target_for_date(date)
        target > 0 && @load_profile[date] > target
      end
      break unless overshooting

      # Find the locked goal with the highest daily share
      heaviest = locked_goals.max_by do |goal|
        book_minutes = estimate_remaining_minutes(goal.book)
        compute_weekday_share(book_minutes, [goal.started_on, Date.current].max, goal.target_completion_date)
      end
      break unless heaviest

      graduation_tier = find_graduation_tier(heaviest)
      break unless graduation_tier

      graduate_goal!(heaviest, graduation_tier)
      @graduated_ids << heaviest.id
    end
  end

  def find_graduation_tier(goal)
    current_end = goal.target_completion_date
    TIERS.each do |tier|
      tier_end = calendar_end(goal.started_on, tier)
      next if tier_end <= current_end
      return tier
    end
    nil
  end

  def graduate_goal!(goal, tier)
    old_start = [goal.started_on, Date.current].max
    old_end = goal.target_completion_date
    book_minutes = estimate_remaining_minutes(goal.book)
    old_share = compute_weekday_share(book_minutes, old_start, old_end)

    # Remove old load
    remove_range_from_profiles(old_start, old_end, old_share)

    # Apply new end date
    new_end = calendar_end(goal.started_on, tier)
    goal.update!(target_completion_date: new_end)

    # Add new load
    new_share = compute_weekday_share(book_minutes, old_start, new_end)
    add_range_to_profiles(old_start, new_end, new_share)

    # Regenerate quotas from today
    regenerate_quotas_from_today!(goal)
  end

  # ─── Phase 4 ────────────────────────────────────────────────────

  def verify_throughput!
    target = annual_pace.round
    tolerance = [2, (target * 0.05).ceil].max

    MAX_ADJUSTMENT_ITERATIONS.times do
      projected = count_projected_completions
      break if projected.between?(target - tolerance, target + tolerance)

      if projected < target - tolerance
        break unless try_shorten_longest_tier!
      else
        break unless try_lengthen_shortest_tier!
      end

      # Stop if the adjustment didn't change projected completions
      # (e.g., all books already finish within the pace window)
      break if count_projected_completions == projected
    end
  end

  def count_projected_completions
    pace_window_end = @pace_start + 365

    locked_count = locked_goals.count do |g|
      g.target_completion_date && g.target_completion_date <= pace_window_end
    end

    placed_count = @placements.count do |entry|
      entry[:goal].target_completion_date <= pace_window_end
    end

    @actual_completed + locked_count + placed_count
  end

  def try_shorten_longest_tier!
    adjustable = @placements
      .reject { |p| locked_goal_ids.include?(p[:goal].id) }
      .sort_by { |p| -TIER_WEEKS[p[:tier]] }

    pace_window_end = @pace_start + 365

    adjustable.each do |entry|
      tier_idx = TIERS.index(entry[:tier])
      next if tier_idx.nil? || tier_idx == 0

      # Skip if the book already finishes within the pace window —
      # shortening won't increase projected completions
      goal = entry[:goal]
      next if goal.target_completion_date <= pace_window_end

      shorter_tier = TIERS[tier_idx - 1]
      new_end = calendar_end(goal.started_on, shorter_tier)
      new_share = compute_weekday_share(entry[:book_minutes], goal.started_on, new_end)
      next if new_share <= 0

      # Remove old placement to evaluate the new one cleanly
      remove_range_from_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])

      unless fits_concurrency_for_adjustment?(goal.started_on, new_end, entry)
        add_range_to_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])
        next
      end

      # Don't shorten if it would exceed the ceiling (preserve leveling)
      if would_overshoot?(goal.started_on, new_end, new_share)
        add_range_to_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])
        next
      end

      goal.update!(target_completion_date: new_end)
      new_placement = { start: goal.started_on, end: new_end, share: new_share, tier: shorter_tier }
      add_range_to_profiles(goal.started_on, new_end, new_share)

      entry[:tier] = shorter_tier
      entry[:placement] = new_placement
      return true
    end

    false
  end

  def try_lengthen_shortest_tier!
    adjustable = @placements
      .reject { |p| locked_goal_ids.include?(p[:goal].id) }
      .sort_by { |p| TIER_WEEKS[p[:tier]] }

    adjustable.each do |entry|
      tier_idx = TIERS.index(entry[:tier])
      next if tier_idx.nil? || tier_idx >= TIERS.length - 1

      longer_tier = TIERS[tier_idx + 1]
      goal = entry[:goal]
      new_end = calendar_end(goal.started_on, longer_tier)
      new_share = compute_weekday_share(entry[:book_minutes], goal.started_on, new_end)
      next if new_share <= 0

      remove_range_from_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])
      goal.update!(target_completion_date: new_end)
      new_placement = { start: goal.started_on, end: new_end, share: new_share, tier: longer_tier }
      add_range_to_profiles(goal.started_on, new_end, new_share)

      entry[:tier] = longer_tier
      entry[:placement] = new_placement
      return true
    end

    false
  end

  def would_overshoot?(start_date, end_date, daily_share)
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      target = target_for_date(date)
      next if target <= 0
      projected = @load_profile[date] + share_for_date(daily_share, date)
      return true if projected > target + CEILING_TOLERANCE
    end
    false
  end

  # Concurrency check that excludes the entry being adjusted (it's temporarily removed)
  def fits_concurrency_for_adjustment?(start_date, end_date, excluded_entry)
    limit = effective_concurrency_limit
    return true unless limit
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      # The excluded entry was already removed from profiles, so current count is accurate
      return false if @concurrent_count[date] >= limit
    end
    true
  end

  # ─── Phase 5 ────────────────────────────────────────────────────

  def generate_quotas_for!(goal)
    goal.daily_quotas.destroy_all
    goal.daily_quotas.reload
    ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!
  end

  def regenerate_quotas_from_today!(goal)
    goal.daily_quotas.where("date >= ?", Date.current).delete_all
    goal.daily_quotas.reload
    ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!(from_date: Date.current)
  end

  # ─── Timeline & Goals ──────────────────────────────────────────

  def locked_goals
    @locked_goals ||= begin
      active_goals = @user.reading_goals
                          .active
                          .where.not(target_completion_date: nil)
                          .includes(:book)

      book_ids_with_sessions_this_week = ReadingSession
        .where(user: @user)
        .where(status: :completed)
        .where("started_at >= ?", Date.current.beginning_of_week(:monday).beginning_of_day)
        .pluck(:book_id)
        .to_set

      active_goals.select { |g| book_ids_with_sessions_this_week.include?(g.book_id) }
    end
  end

  def locked_goal_ids
    @locked_goal_ids ||= locked_goals.map(&:id).to_set
  end

  def gather_schedulable_goals
    goals = @user.reading_goals
                 .where(status: [:queued, :active])
                 .where(auto_scheduled: true)
                 .where.not(position: nil)
                 .includes(:book)
                 .order(:position)
                 .reject { |g| locked_goal_ids.include?(g.id) }

    # Track which goals are stale (active with sessions, but not this week)
    @stale_goal_ids = goals.select { |g| g.active? && g.has_reading_sessions? }.map(&:id).to_set

    goals
  end

  # ─── Calendar Helpers ──────────────────────────────────────────

  # End date is always computed from the week's Monday, so tier
  # boundaries always land on Sundays regardless of start day.
  def calendar_end(start_date, tier)
    ref_monday = start_date.beginning_of_week(:monday)
    ref_monday + (TIER_WEEKS[tier] * 7) - 1
  end

  def count_reading_days(start_date, end_date)
    return 0 if start_date.nil? || end_date.nil?
    if @user.includes_weekends?
      (end_date - start_date).to_i + 1
    else
      (start_date..end_date).count { |d| !d.on_weekend? }
    end
  end

  def reading_day?(date)
    @user.includes_weekends? || !date.on_weekend?
  end

  # ─── Estimates ─────────────────────────────────────────────────

  def estimate_remaining_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.density_modifier)
    return 60 if wpm.zero?
    (book.remaining_words.to_f / wpm).ceil
  end

  def annual_pace
    return 0 unless @user.reading_pace_value&.positive?
    case @user.reading_pace_type
    when "books_per_year"  then @user.reading_pace_value.to_f
    when "books_per_month" then @user.reading_pace_value * 12.0
    when "books_per_week"  then @user.reading_pace_value * 52.0
    else 0
    end
  end

  def throughput_pace?
    %w[books_per_year books_per_month books_per_week].include?(@user.reading_pace_type) &&
      @user.reading_pace_value&.positive?
  end

  def effective_concurrency_limit
    @user.concurrency_limit || @user.max_concurrent_books
  end

  # ─── Metrics Helpers ────────────────────────────────────────────

  # Show the target the user actually experiences on a reading day,
  # not the raw average that includes zero-target weekends.
  def effective_daily_target(avg_target)
    return avg_target unless avg_target&.positive?
    @user.skip? ? avg_target * 7.0 / 5.0 : avg_target
  end

  def default_metrics
    { pace_status: nil, deficit: 0, derived_target: 0,
      projected_completions: 0, pace_target: 0, queue_depth: 0, queue_warning: nil,
      concurrency_hint: nil, ahead_suggestion: nil }
  end

  def pace_status_label(target)
    return "on pace" if @deficit.abs < 0.5
    behind = @deficit.round
    if behind > 0
      "#{behind} #{'book'.pluralize(behind)} behind"
    else
      "#{behind.abs} #{'book'.pluralize(behind.abs)} ahead"
    end
  end

  def queue_warning(queued_count, target, projected)
    shortfall = target - projected
    return nil if shortfall <= 0
    "Add #{shortfall}+ books to maintain your pace"
  end

  def concurrency_hint(daily_target, target)
    return nil unless daily_target&.positive? && target > 0
    limit = effective_concurrency_limit
    return nil unless limit

    window = build_pace_window([target, 1].max)
    return nil if window.empty?

    avg_book_minutes = window.sum { |book| full_book_minutes(book) }.to_f / window.size
    takt_days = 365.0 / target
    avg_book_days = avg_book_minutes / daily_target
    min_concurrent = (avg_book_days / takt_days).ceil

    return nil if limit >= min_concurrent

    "Your schedule could flow more smoothly with #{min_concurrent} concurrent books"
  end

  def ahead_suggestion
    active_goals = @user.reading_goals.active.includes(:book)
    all_done = active_goals.empty? || active_goals.all? { |g| g.book.remaining_pages <= 0 }
    return nil unless all_done

    next_queued = @user.reading_goals
                       .where(status: :queued, auto_scheduled: true)
                       .where.not(position: nil)
                       .order(:position)
                       .includes(:book)
                       .first
    return nil unless next_queued

    "You're ahead of schedule! Consider starting: #{next_queued.book.title}"
  end
end
