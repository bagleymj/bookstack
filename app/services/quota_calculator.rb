class QuotaCalculator
  def initialize(reading_goal)
    @goal = reading_goal
    @book = reading_goal.book
  end

  def generate_quotas!
    return if @goal.daily_quotas.any?

    pages_remaining = @book.remaining_pages
    reading_dates = calculate_reading_dates

    return if reading_dates.empty?

    pages_per_day = (pages_remaining.to_f / reading_dates.size).ceil
    remaining = pages_remaining

    reading_dates.each do |date|
      break if remaining <= 0

      pages_today = [pages_per_day, remaining].min
      remaining -= pages_today

      @goal.daily_quotas.create!(
        date: date,
        target_pages: pages_today,
        actual_pages: 0,
        status: :pending
      )
    end
  end

  private

  def calculate_reading_dates
    (@goal.started_on..@goal.target_completion_date).select do |date|
      @goal.include_weekends? || !date.on_weekend?
    end
  end
end
