class ReadingListScheduler
  def initialize(user)
    @user = user
  end

  def schedule!
    slots = build_slot_timeline
    schedulable_goals = gather_schedulable_goals

    schedulable_goals.each do |goal|
      earliest_slot = slots.min_by { |s| s[:free_date] }
      start_date = [earliest_slot[:free_date], Date.current].max

      total_minutes = estimate_total_minutes(goal.book)
      end_date = walk_calendar(start_date, total_minutes)

      goal.update!(
        started_on: start_date,
        target_completion_date: end_date,
        include_weekends: @user.includes_weekends?,
        status: start_date <= Date.current ? :active : :active
      )

      # Regenerate quotas
      goal.daily_quotas.destroy_all
      goal.daily_quotas.reload
      ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!

      earliest_slot[:free_date] = end_date + 1.day
    end
  end

  private

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

  # Walk calendar from start_date, subtracting available minutes per day
  # until total_minutes is consumed. Returns the end date.
  def walk_calendar(start_date, total_minutes)
    remaining = total_minutes.to_f
    current_date = start_date

    loop do
      minutes_today = daily_available_minutes(current_date)

      if minutes_today > 0
        remaining -= minutes_today
        return current_date if remaining <= 0
      end

      current_date += 1.day

      # Safety: cap at 2 years out
      break if current_date > start_date + 730.days
    end

    current_date
  end

  def daily_available_minutes(date)
    if date.on_weekend?
      @user.weekend_reading_minutes
    else
      @user.weekday_reading_minutes
    end
  end
end
