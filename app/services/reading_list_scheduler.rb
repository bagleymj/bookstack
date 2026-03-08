class ReadingListScheduler
  # Week-based tiers snap to Monday; month-based snap to 1st of month.
  # Flexible week tiers (1-8 weeks) let books span natural durations
  # without gaps between the 2-week and month boundaries.
  WEEK_TIERS = (1..8).map { |w| { type: :weeks, count: w } }.freeze
  MONTH_TIERS = [1, 2, 3, 6].map { |m| { type: :months, count: m } }.freeze
  ALL_TIERS = (WEEK_TIERS + MONTH_TIERS).freeze

  BUDGET_TOLERANCE = 10 # ±10 minutes from target share

  def initialize(user)
    @user = user
    @max_concurrent = user.max_concurrent_books
  end

  def schedule!
    @daily_budget = compute_daily_budget

    timeline = build_locked_timeline
    schedulable = gather_schedulable_goals
    remaining_in_queue = schedulable.size

    schedulable.each do |goal|
      book_minutes = estimate_total_minutes(goal.book)
      placement = find_best_placement(timeline, book_minutes, remaining_in_queue)

      goal.update!(
        started_on: placement[:start],
        target_completion_date: placement[:end],
        include_weekends: @user.includes_weekends?,
        status: :active
      )

      goal.daily_quotas.destroy_all
      goal.daily_quotas.reload
      ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!

      timeline << { start: placement[:start], end: placement[:end], share: placement[:share] }
      remaining_in_queue -= 1
    end
  end

  private

  # --- Budget ---

  # Build a rolling window of exactly `annual_pace` books (e.g. 50 for
  # 50 books/year). Fill reading-list-first (by queue position), then
  # backfill with most recently completed books. This keeps the budget
  # predictive — it always represents one full pace cycle — without
  # being dragged down by distant history or spiked by outliers.
  def compute_daily_budget
    window_size = annual_pace.round
    return fallback_daily_budget if window_size <= 0

    window = build_budget_window(window_size)
    return fallback_daily_budget if window.empty?

    avg_minutes = window.sum { |book| full_book_minutes(book) }.to_f / window.size
    books_per_day = annual_pace / 365.0
    avg_minutes * books_per_day
  end

  # Reading list books first (up to window_size), then recent completions.
  def build_budget_window(window_size)
    # Reading list books in queue order (limited to window)
    list_books = @user.reading_goals
                      .where(auto_scheduled: true)
                      .where.not(position: nil)
                      .where(status: [:queued, :active])
                      .includes(:book)
                      .order(:position)
                      .limit(window_size)
                      .map(&:book)

    return list_books if list_books.size >= window_size

    # Backfill with most recently completed books
    remaining = window_size - list_books.size
    exclude_ids = list_books.map(&:id)
    completed = @user.books
                     .finished
                     .where.not(id: exclude_ids)
                     .order(completed_at: :desc)
                     .limit(remaining)

    list_books + completed.to_a
  end

  # Full reading time for a book (total words, not remaining).
  # Used for budget calculation so completed books aren't counted as 0.
  def full_book_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60 if wpm.zero?
    (book.total_words.to_f / wpm).ceil
  end

  def fallback_daily_budget
    @user.derive_daily_minutes_from_pace || default_daily_minutes
  end

  def default_daily_minutes
    (@user.weekday_reading_minutes * 5 + @user.weekend_reading_minutes * 2) / 7.0
  end

  # --- Placement ---

  # Collect the earliest viable candidate from each tier, then pick the
  # one that best balances start date and daily share. Prefers earliest
  # start (to fill concurrent slots and avoid gaps), breaking ties by
  # the share closest to the ideal per-slot target.
  def find_best_placement(timeline, book_minutes, remaining_in_queue)
    target_share = @daily_budget / [@max_concurrent, 1].max.to_f
    candidates = []

    ALL_TIERS.each do |tier|
      placement = find_opening_for_tier(timeline, tier, book_minutes, remaining_in_queue)
      candidates << placement if placement
    end

    return default_placement(book_minutes) if candidates.empty?

    candidates.min_by { |c| [c[:start], (c[:share] - target_share).abs] }
  end

  # Walk snap boundaries for a given tier, looking for the first date
  # where the book's daily share fits within the per-slot budget.
  def find_opening_for_tier(timeline, tier, book_minutes, remaining_in_queue)
    date = next_reading_day(Date.current)

    50.times do
      snapped = snap_to_boundary(date, tier)
      end_date = calendar_end(snapped, tier)
      reading_days = count_reading_days(snapped, end_date)
      break if reading_days <= 0

      daily_share = book_minutes.to_f / reading_days

      active = timeline.select { |e| e[:start] <= snapped && e[:end] >= snapped }
      if active.size < @max_concurrent
        active_total = active.sum { |e| e[:share] }
        gap = @daily_budget - active_total
        empty_slots = @max_concurrent - active.size
        slots_to_fill = [empty_slots, remaining_in_queue].min
        max_share = (slots_to_fill > 0 ? gap / slots_to_fill.to_f : gap) + BUDGET_TOLERANCE

        return { start: snapped, end: end_date, share: daily_share } if daily_share <= max_share
      end

      # Advance to next snap boundary for this tier
      date = next_boundary(snapped, tier)
    end

    nil
  end

  # Advance past the current snap boundary to the next one for this tier.
  def next_boundary(current_snap, tier)
    if tier[:type] == :weeks
      current_snap + 7 # next Monday
    else
      next_first_of_month(current_snap + 1)
    end
  end

  # Fallback when no tier fits after exhausting openings.
  def default_placement(book_minutes)
    start = next_reading_day(Date.current)
    share = @daily_budget / [@max_concurrent, 1].max.to_f
    share = [share, 1].max
    reading_days = [(book_minutes.to_f / share).ceil, 1].max
    end_date = advance_by_reading_days(start, reading_days)
    { start: start, end: end_date, share: share }
  end

  # --- Snap & calendar ---

  def snap_to_boundary(date, tier)
    if tier[:type] == :weeks
      next_weekday(date, :monday)
    else
      next_first_of_month(date)
    end
  end

  def calendar_end(start_date, tier)
    if tier[:type] == :weeks
      start_date + (tier[:count] * 7) - 1
    else
      case tier[:count]
      when 1 then start_date.end_of_month
      when 2 then (start_date + 1.month).end_of_month
      when 3 then (start_date + 2.months).end_of_month
      when 6 then (start_date + 5.months).end_of_month
      end
    end
  end

  # --- Timeline ---

  def build_locked_timeline
    locked_goals.map do |goal|
      book_minutes = estimate_total_minutes(goal.book)
      days = count_reading_days(goal.started_on, goal.target_completion_date)
      daily_share = days > 0 ? book_minutes.to_f / days : 0

      { start: goal.started_on, end: goal.target_completion_date, share: daily_share }
    end
  end

  def locked_goals
    @locked_goals ||= @user.reading_goals
                            .active
                            .where.not(target_completion_date: nil)
                            .includes(:book)
                            .select(&:has_reading_sessions?)
  end

  # --- Schedulable goals ---

  def gather_schedulable_goals
    @user.reading_goals
         .where(status: [:queued, :active])
         .where(auto_scheduled: true)
         .where.not(position: nil)
         .includes(:book)
         .order(:position)
         .reject { |g| g.active? && g.has_reading_sessions? }
  end

  # --- Day counting ---

  def count_reading_days(start_date, end_date)
    return 0 if start_date.nil? || end_date.nil?

    if @user.includes_weekends?
      (end_date - start_date).to_i + 1
    else
      (start_date..end_date).count { |d| !d.on_weekend? }
    end
  end

  def advance_by_reading_days(start_date, reading_days)
    return start_date if reading_days <= 1

    if @user.includes_weekends?
      start_date + reading_days - 1
    else
      date = start_date
      counted = 0
      loop do
        counted += 1 unless date.on_weekend?
        return date if counted >= reading_days
        date += 1
      end
    end
  end

  # --- Date helpers ---

  def next_weekday(date, day)
    target_wday = day == :monday ? 1 : 6
    return date if date.wday == target_wday
    days_ahead = (target_wday - date.wday) % 7
    date + days_ahead
  end

  def next_first_of_month(date)
    return date if date.day == 1
    date.next_month.beginning_of_month
  end

  def next_reading_day(date)
    return date if @user.includes_weekends?
    date += 1 while date.on_weekend?
    date
  end

  # --- Estimates ---

  def estimate_total_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
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
end
