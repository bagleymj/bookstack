class ProfileAwareQuotaCalculator
  def initialize(reading_goal, user)
    @goal = reading_goal
    @book = reading_goal.book
    @user = user
  end

  # Distributes pages proportionally to available minutes per day.
  # Days with more reading time get more pages.
  def generate_quotas!(from_date: nil)
    return if from_date.nil? && @goal.daily_quotas.any?

    pages_remaining = @book.remaining_pages
    reading_dates = calculate_reading_dates(from_date: from_date)
    return if reading_dates.empty? || pages_remaining <= 0

    # Calculate minutes for each day
    day_minutes = reading_dates.map { |date| daily_minutes(date) }
    total_minutes = day_minutes.sum.to_f

    return if total_minutes.zero?

    # Distribute pages proportionally to minutes, then fix rounding
    raw_pages = day_minutes.map { |m| (m / total_minutes) * pages_remaining }
    floored = raw_pages.map { |p| p.floor }
    remainder = pages_remaining - floored.sum

    # Distribute remainder to days with largest fractional parts
    fractionals = raw_pages.each_with_index.map { |p, i| [p - p.floor, i] }
    fractionals.sort_by! { |f, _| -f }
    remainder.times { |r| floored[fractionals[r][1]] += 1 }

    reading_dates.each_with_index do |date, i|
      next if floored[i] <= 0

      @goal.daily_quotas.create!(
        date: date,
        target_pages: floored[i],
        actual_pages: 0,
        status: :pending
      )
    end
  end

  private

  def calculate_reading_dates(from_date: nil)
    return [] if @goal.started_on.nil? || @goal.target_completion_date.nil?

    start_date = from_date || @goal.started_on
    (start_date..@goal.target_completion_date).select do |date|
      minutes = daily_minutes(date)
      minutes > 0
    end
  end

  def daily_minutes(date)
    if date.on_weekend?
      @user.weekend_target
    else
      @user.weekday_reading_minutes
    end
  end
end
