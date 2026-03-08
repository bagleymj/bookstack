class ReadingListScheduler
  TIERS = [:week, :month, :quarter, :half_year].freeze
  BUDGET_TOLERANCE = 10 # ±10 minutes from target share

  def initialize(user)
    @user = user
    @max_concurrent = user.max_concurrent_books
  end

  def schedule!
    @daily_budget = compute_daily_budget
    compute_weekend_budgets

    timeline = build_locked_timeline
    schedulable = gather_schedulable_goals

    schedulable.each do |goal|
      book_minutes = estimate_total_minutes(goal.book)
      placement = find_best_placement(timeline, book_minutes)

      goal.update!(
        started_on: placement[:start],
        target_completion_date: placement[:end],
        status: :active
      )

      goal.daily_quotas.destroy_all
      goal.daily_quotas.reload
      ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!

      timeline << { start: placement[:start], end: placement[:end], share: placement[:share] }
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
    (@user.weekday_reading_minutes * 5 + @user.weekend_budget * 2) / 7.0
  end

  def compute_weekend_budgets
    weekly_total = @daily_budget * 7
    case @user.weekend_mode
    when "skip"
      @weekday_budget = weekly_total / 5.0
      @weekend_budget = 0
    when "same"
      @weekday_budget = @weekend_budget = weekly_total / 7.0
    when "capped"
      @weekend_budget = @user.weekend_reading_minutes.to_f
      @weekday_budget = (weekly_total - @weekend_budget * 2) / 5.0
    end
  end

  def budget_for_date(date)
    date.on_weekend? ? @weekend_budget : @weekday_budget
  end

  def share_for_date(share, date)
    return share unless @user.capped? && date.on_weekend? && @weekday_budget > 0
    share * (@weekend_budget / @weekday_budget)
  end

  # --- Placement ---

  # For each tier (shortest first), walk snap boundaries looking for the
  # first opening where the book fits. This ensures a week read at a later
  # opening always beats a month read at an earlier one — short tiers get
  # every chance before the scheduler stretches to a longer one.
  def find_best_placement(timeline, book_minutes)
    TIERS.each do |tier|
      placement = find_opening_for_tier(timeline, tier, book_minutes)
      return placement if placement
    end

    default_placement(book_minutes)
  end

  # Walk snap boundaries for a given tier, looking for the first date
  # where the book fits under the ceiling across its entire span.
  def find_opening_for_tier(timeline, tier, book_minutes)
    date = next_reading_day(Date.current)

    50.times do
      snapped = next_reading_day(snap_to_boundary(date, tier))
      end_date = calendar_end(snapped, tier)
      reading_days = count_reading_days(snapped, end_date)
      break if reading_days <= 0

      daily_share = compute_weekday_share(book_minutes, snapped, end_date)

      if fits_across_span?(timeline, snapped, end_date, daily_share)
        return { start: snapped, end: end_date, share: daily_share }
      end

      date = next_boundary(snapped, tier)
    end

    nil
  end

  # Compute the weekday share for a book across a date span.
  # For skip/same modes, this is simply book_minutes / reading_days.
  # For capped mode, weekend days count as fractional days based on the
  # ratio of weekend_budget to weekday_budget.
  def compute_weekday_share(book_minutes, start_date, end_date)
    if @user.capped? && @weekday_budget > 0
      ratio = @weekend_budget / @weekday_budget
      weekday_count = (start_date..end_date).count { |d| !d.on_weekend? }
      weekend_count = (start_date..end_date).count { |d| d.on_weekend? }
      effective_days = weekday_count + weekend_count * ratio
      effective_days > 0 ? book_minutes.to_f / effective_days : 0
    else
      reading_days = count_reading_days(start_date, end_date)
      reading_days > 0 ? book_minutes.to_f / reading_days : 0
    end
  end

  # Check viability (concurrent cap + budget not met) and fit (ceiling)
  # at every transition point across the book's entire span.
  def fits_across_span?(timeline, snapped, end_date, daily_share)
    check_dates = [snapped]
    timeline.each do |e|
      check_dates << e[:start] if e[:start] > snapped && e[:start] <= end_date
      check_dates << (e[:end] + 1) if e[:end] >= snapped && e[:end] < end_date
    end

    check_dates.uniq.all? do |date|
      next true if !@user.includes_weekends? && date.on_weekend?

      date_budget = budget_for_date(date)
      date_share = share_for_date(daily_share, date)

      active = timeline.select { |e| e[:start] <= date && e[:end] >= date }
      active_total = active.sum { |e| share_for_date(e[:share], date) }
      active.size < @max_concurrent &&
        active_total < date_budget &&
        active_total + date_share <= date_budget + BUDGET_TOLERANCE
    end
  end

  # Advance past the current snap boundary to the next one for this tier.
  def next_boundary(current_snap, tier)
    case tier
    when :week
      current_snap + 7 # next Monday
    when :month, :quarter, :half_year
      next_first_of_month(current_snap + 1)
    end
  end

  # Fallback when no tier fits after exhausting openings.
  def default_placement(book_minutes)
    start = next_reading_day(Date.current)
    share = @weekday_budget / [@max_concurrent, 1].max.to_f
    share = [share, 1].max
    reading_days = [(book_minutes.to_f / share).ceil, 1].max
    end_date = advance_by_reading_days(start, reading_days)
    { start: start, end: end_date, share: share }
  end

  # --- Snap & calendar ---

  def snap_to_boundary(date, tier)
    case tier
    when :week
      next_weekday(date, :monday)
    when :month, :quarter, :half_year
      next_first_of_month(date)
    end
  end

  def calendar_end(start_date, tier)
    case tier
    when :week      then start_date + 6
    when :month     then start_date.end_of_month
    when :quarter   then (start_date + 2.months).end_of_month
    when :half_year then (start_date + 5.months).end_of_month
    end
  end

  # --- Timeline ---

  def build_locked_timeline
    locked_goals.map do |goal|
      book_minutes = estimate_total_minutes(goal.book)
      daily_share = compute_weekday_share(book_minutes, goal.started_on, goal.target_completion_date)

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
