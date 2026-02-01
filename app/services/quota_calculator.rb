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

    num_days = reading_dates.size
    base_pages = pages_remaining / num_days
    extra_days = pages_remaining % num_days

    reading_dates.each_with_index do |date, i|
      pages_today = base_pages + (i < extra_days ? 1 : 0)
      next if pages_today <= 0

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
