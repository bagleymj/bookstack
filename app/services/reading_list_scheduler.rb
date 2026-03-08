class ReadingListScheduler
  DURATION_TIERS = {
    week:      { max_minutes: 150,  snap: :monday,         label: "1-week read" },
    two_weeks: { max_minutes: 400,  snap: :monday,         label: "2-week read" },
    month:     { max_minutes: 800,  snap: :first_of_month, label: "1-month read" },
    quarter:   { max_minutes: 1600, snap: :first_of_month, label: "3-month read" },
    half_year: { max_minutes: Float::INFINITY, snap: :first_of_month, label: "6-month read" }
  }.freeze

  def initialize(user)
    @user = user
    @max_concurrent = user.max_concurrent_books
  end

  def schedule!
    all_goals = locked_goals + gather_schedulable_goals
    @daily_budget = compute_daily_budget(all_goals)

    timeline = build_locked_timeline
    schedulable = gather_schedulable_goals

    schedulable.each do |goal|
      book_minutes = estimate_total_minutes(goal.book)
      tier = duration_tier(book_minutes)

      start_date = find_start_date(timeline, tier, book_minutes)
      end_date = calendar_end(start_date, tier)
      duration_days = count_reading_days(start_date, end_date)
      daily_share = duration_days > 0 ? book_minutes.to_f / duration_days : book_minutes.to_f

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

  # --- Tier & calendar logic ---

  def duration_tier(book_minutes)
    case book_minutes
    when 0..150    then :week
    when 151..400  then :two_weeks
    when 401..800  then :month
    when 801..1600 then :quarter
    else :half_year
    end
  end

  def snap_to_boundary(date, tier)
    case DURATION_TIERS[tier][:snap]
    when :monday
      next_weekday(date, :monday)
    when :first_of_month
      next_first_of_month(date)
    end
  end

  def calendar_end(start_date, tier)
    case tier
    when :week      then start_date + 6
    when :two_weeks then start_date + 13
    when :month     then start_date.end_of_month
    when :quarter   then (start_date + 2.months).end_of_month
    when :half_year then (start_date + 5.months).end_of_month
    end
  end

  # --- Placement ---

  def find_start_date(timeline, tier, book_minutes)
    date = Date.current
    budget_cap = @daily_budget * 1.1

    100.times do
      snapped = snap_to_boundary(date, tier)
      end_date = calendar_end(snapped, tier)
      days = count_reading_days(snapped, end_date)
      daily_share = days > 0 ? book_minutes.to_f / days : book_minutes.to_f

      active = timeline.select { |e| e[:start] <= snapped && e[:end] >= snapped }

      if active.size < @max_concurrent && (active.sum { |e| e[:share] } + daily_share) <= budget_cap
        return snapped
      end

      next_end = active.map { |e| e[:end] }.min
      date = next_end ? next_end + 1 : date + 1
    end

    snap_to_boundary(Date.current, tier)
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

  # --- Estimates ---

  def estimate_total_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60 if wpm.zero?

    (book.remaining_words.to_f / wpm).ceil
  end

  # Normalize pace to books/year for budget projection.
  def annual_pace
    return 0 unless @user.reading_pace_value&.positive?

    case @user.reading_pace_type
    when "books_per_year"  then @user.reading_pace_value.to_f
    when "books_per_month" then @user.reading_pace_value * 12.0
    when "books_per_week"  then @user.reading_pace_value * 52.0
    else 0
    end
  end

  # Days between completing one book and the next.
  def pace_completion_interval
    pace = annual_pace
    return 0 if pace <= 0
    (365.0 / pace).round
  end
end
