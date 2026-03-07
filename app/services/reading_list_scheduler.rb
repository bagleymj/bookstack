class ReadingListScheduler
  SNAP_PERIODS = [2, 7, 14, 30, 90, 180].freeze

  def initialize(user)
    @user = user
  end

  def schedule!
    slots = build_slot_timeline
    schedulable_goals = gather_schedulable_goals
    per_slot_minutes = effective_daily_minutes_per_slot

    schedulable_goals.each do |goal|
      earliest_slot = slots.min_by { |s| s[:free_date] }
      start_date = [earliest_slot[:free_date], Date.current].max

      total_minutes = estimate_total_minutes(goal.book)
      raw_days = per_slot_minutes > 0 ? (total_minutes.to_f / per_slot_minutes).ceil : 7
      snapped_days = snap_to_period(raw_days)
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

  def effective_daily_minutes_per_slot
    total = @user.derive_daily_minutes_from_pace
    total ||= (@user.weekday_reading_minutes * 5 + @user.weekend_reading_minutes * 2) / 7.0
    total.to_f / @user.max_concurrent_books
  end

  # Build initial slot availability from locked goals (goals with sessions)
  def build_slot_timeline
    max_slots = @user.max_concurrent_books
    slots = Array.new(max_slots) { { free_date: Date.current } }

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
