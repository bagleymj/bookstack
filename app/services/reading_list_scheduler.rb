class ReadingListScheduler
  SNAP_PERIODS = [2, 7, 14, 30, 90, 180].freeze

  def initialize(user)
    @user = user
  end

  def schedule!
    slots = build_slot_timeline
    schedulable_goals = gather_schedulable_goals
    default_duration = pace_book_duration
    per_slot_minutes = effective_daily_minutes_per_slot

    schedulable_goals.each do |goal|
      earliest_slot = slots.min_by { |s| s[:free_date] }
      earliest_date = [earliest_slot[:free_date], Date.current].max

      # Start with pace-derived duration. Every book gets the same window
      # so the plan projects to the target pace.
      snapped_days = default_duration

      # Extend for books that physically can't fit — if the reading time
      # exceeds the slot's daily budget × duration, bump to the next period.
      total_minutes = estimate_total_minutes(goal.book)
      min_days = per_slot_minutes > 0 ? (total_minutes.to_f / per_slot_minutes).ceil : snapped_days
      while snapped_days < min_days && snapped_days < SNAP_PERIODS.last
        snapped_days = next_snap_period(snapped_days)
      end

      start_date = snap_start_date(earliest_date, snapped_days)
      end_date = start_date + snapped_days - 1

      goal.update!(
        started_on: start_date,
        target_completion_date: end_date,
        include_weekends: @user.includes_weekends?,
        status: :active
      )

      goal.daily_quotas.destroy_all
      goal.daily_quotas.reload
      ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!

      earliest_slot[:free_date] = end_date + 1.day
    end
  end

  private

  # The standard duration each book gets, derived from the pace target.
  # With 50 books/year and 3 concurrent: interval=7, duration=7*3=21 → snap to 14.
  # This ensures the plan projects to ~50 completions/year.
  def pace_book_duration
    interval = pace_completion_interval
    if interval > 0
      snap_to_period(interval * @user.max_concurrent_books)
    else
      # minutes_per_day pace: fall back to reading-speed estimate
      7
    end
  end

  def next_snap_period(current)
    idx = SNAP_PERIODS.index(current)
    return SNAP_PERIODS.last if idx.nil? || idx >= SNAP_PERIODS.length - 1
    SNAP_PERIODS[idx + 1]
  end

  # Snap raw_days to the nearest period, biased toward gentler (longer).
  # Uses a 40% threshold: snap down only if raw_days falls in the bottom 40%
  # of the gap between two snap points. Otherwise snap up.
  def snap_to_period(raw_days)
    return SNAP_PERIODS.first if raw_days <= SNAP_PERIODS.first

    SNAP_PERIODS.each_cons(2) do |lower, upper|
      next if raw_days > upper
      midpoint = lower + (upper - lower) * 0.4
      return raw_days > midpoint ? upper : lower
    end

    SNAP_PERIODS.last
  end

  # Snap a start date to a clean boundary based on the book's duration:
  #   Weekend reads (2 days) → Saturday
  #   Weekly reads (7/14 days) → Monday
  #   Monthly+ reads (30/90/180 days) → 1st of the month
  def snap_start_date(earliest_date, snapped_days)
    case snapped_days
    when 2
      next_weekday(earliest_date, :saturday)
    when 7, 14
      next_weekday(earliest_date, :monday)
    else # 30, 90, 180
      next_first_of_month(earliest_date)
    end
  end

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

  def effective_daily_minutes_per_slot
    total = @user.derive_daily_minutes_from_pace
    total ||= (@user.weekday_reading_minutes * 5 + @user.weekend_reading_minutes * 2) / 7.0
    total.to_f / @user.max_concurrent_books
  end

  # Build initial slot availability from locked goals (goals with sessions).
  # Empty slots are staggered by the pace interval so books spread out
  # over time instead of all starting on the same day.
  def build_slot_timeline
    max_slots = @user.max_concurrent_books
    stagger = pace_stagger_days
    slots = Array.new(max_slots) { |i| { free_date: Date.current + (i * stagger) } }

    locked_goals = @user.reading_goals
                        .active
                        .where.not(target_completion_date: nil)
                        .includes(:book)

    locked_goals.each do |goal|
      next unless goal.has_reading_sessions?

      # This goal occupies a slot until its end date
      earliest_slot = slots.min_by { |s| s[:free_date] }
      end_after = goal.target_completion_date + 1.day
      if end_after > earliest_slot[:free_date]
        earliest_slot[:free_date] = end_after
      end
    end

    slots
  end

  # How many days to stagger between slots, derived from the user's pace.
  # With 50 books/year → 7 days between each slot opening.
  # With 1 concurrent book → no stagger needed.
  def pace_stagger_days
    return 0 if @user.max_concurrent_books <= 1

    interval = pace_completion_interval
    return 0 if interval <= 0

    interval
  end

  # Days between finishing one book and the next, based on pace setting.
  def pace_completion_interval
    return 0 unless @user.reading_pace_value&.positive?

    case @user.reading_pace_type
    when "books_per_year"
      (365.0 / @user.reading_pace_value).round
    when "books_per_month"
      (30.0 / @user.reading_pace_value).round
    when "books_per_week"
      (7.0 / @user.reading_pace_value).round
    else
      0
    end
  end

  # Schedulable = queued + active auto_scheduled without sessions, ordered by position
  def gather_schedulable_goals
    @user.reading_goals
         .where(status: [:queued, :active])
         .where(auto_scheduled: true)
         .where.not(position: nil)
         .includes(:book)
         .order(:position)
         .reject { |g| g.active? && g.has_reading_sessions? }
  end

  def estimate_total_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60 if wpm.zero? # fallback: 1 hour

    (book.remaining_words.to_f / wpm).ceil
  end
end
