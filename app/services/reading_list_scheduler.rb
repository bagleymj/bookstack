class ReadingListScheduler
  def initialize(user)
    @user = user
    @max_concurrent = user.max_concurrent_books
  end

  def schedule!
    all_goals = locked_goals + gather_schedulable_goals
    @daily_budget = compute_daily_budget(all_goals)

    timeline = build_locked_timeline
    schedulable = gather_schedulable_goals
    remaining_in_queue = schedulable.size

    schedulable.each do |goal|
      book_minutes = estimate_total_minutes(goal.book)

      start_date, daily_share = find_placement(timeline, book_minutes, remaining_in_queue)
      reading_days = [(book_minutes.to_f / daily_share).ceil, 1].max
      end_date = advance_by_reading_days(start_date, reading_days)

      goal.update!(
        started_on: start_date,
        target_completion_date: end_date,
        include_weekends: @user.includes_weekends?,
        status: :active
      )

      goal.daily_quotas.destroy_all
      goal.daily_quotas.reload
      ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!

      timeline << { start: start_date, end: end_date, share: daily_share }
      remaining_in_queue -= 1
    end
  end

  private

  # --- Budget ---

  # Project the list's average book across the full year pace.
  # "If my typical book looks like the average of my list, how much
  # daily reading does 50 books/year require?"
  def compute_daily_budget(all_goals)
    return fallback_daily_budget if all_goals.empty?

    total_minutes = all_goals.sum { |g| estimate_total_minutes(g.book) }
    return fallback_daily_budget if total_minutes <= 0

    pace = annual_pace
    return fallback_daily_budget if pace <= 0

    avg_book_minutes = total_minutes.to_f / all_goals.size
    books_per_day = pace / 365.0
    avg_book_minutes * books_per_day
  end

  def fallback_daily_budget
    @user.derive_daily_minutes_from_pace || default_daily_minutes
  end

  def default_daily_minutes
    (@user.weekday_reading_minutes * 5 + @user.weekend_reading_minutes * 2) / 7.0
  end

  # --- Placement ---

  # Find the earliest date with slot capacity and assign a daily share.
  # The share = available gap / empty slots to fill, so concurrent books
  # each get an equal slice of the budget. Books that start when fewer
  # slots are occupied get a larger share (and thus shorter duration).
  def find_placement(timeline, book_minutes, remaining_in_queue)
    date = next_reading_day(Date.current)

    200.times do
      active = timeline.select { |e| e[:start] <= date && e[:end] >= date }
      active_count = active.size

      if active_count < @max_concurrent
        active_total = active.sum { |e| e[:share] }
        gap = @daily_budget - active_total
        empty_slots = @max_concurrent - active_count
        slots_to_fill = [empty_slots, remaining_in_queue].min
        daily_share = slots_to_fill > 0 ? gap / slots_to_fill.to_f : gap

        return [date, daily_share] if daily_share >= 1
      end

      next_end = active.map { |e| e[:end] }.min
      date = next_end ? next_reading_day(next_end + 1) : next_reading_day(date + 1)
    end

    # Fallback: equal share from today
    share = @daily_budget / [@max_concurrent, 1].max.to_f
    [next_reading_day(Date.current), [share, 1].max]
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

  # Advance from start_date by N reading days, returning the end date.
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
