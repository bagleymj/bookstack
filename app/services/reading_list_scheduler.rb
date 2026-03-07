class ReadingListScheduler
  SNAP_PERIODS = [2, 7, 14, 30, 90, 180].freeze

  def initialize(user)
    @user = user
  end

  def schedule!
    slots = build_slot_timeline
    schedulable_goals = gather_schedulable_goals
    default_duration = pace_book_duration
    interval = pace_completion_interval
    per_slot_minutes = effective_daily_minutes_per_slot

    schedulable_goals.each do |goal|
      earliest_slot = slots.min_by { |s| s[:free_date] }
      earliest_date = [earliest_slot[:free_date], Date.current].max

      # Start with pace-derived duration so the plan projects to the target.
      duration = default_duration

      # Extend for books too long to fit — add intervals to maintain rhythm.
      total_minutes = estimate_total_minutes(goal.book)
      min_days = per_slot_minutes > 0 ? (total_minutes.to_f / per_slot_minutes).ceil : duration
      step = [interval, 7].max
      while duration < min_days
        duration += step
      end

      start_date = snap_start_date(earliest_date, duration)
      end_date = start_date + duration - 1

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

  # The duration each book gets, derived directly from the pace target.
  # NOT snapped — the pace determines the exact duration.
  # With 50 books/year and 3 concurrent: 7 × 3 = 21 days per book.
  def pace_book_duration
    interval = pace_completion_interval
    return 7 if interval <= 0
    interval * @user.max_concurrent_books
  end

  # Snap a start date to a clean boundary based on the book's duration:
  #   Weekend reads (≤4 days) → Saturday
  #   Weekly reads (5–21 days) → Monday
  #   Monthly+ reads (22+ days) → 1st of the month
  def snap_start_date(earliest_date, duration_days)
    if duration_days <= 4
      next_weekday(earliest_date, :saturday)
    elsif duration_days <= 21
      next_weekday(earliest_date, :monday)
    else
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
