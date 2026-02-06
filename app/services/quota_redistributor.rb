class QuotaRedistributor
  def initialize(reading_goal, from_date: Date.current)
    @goal = reading_goal
    @book = reading_goal.book
    @from_date = from_date
  end

  def redistribute!
    mark_past_incomplete_as_missed!
    redistribute_remaining_pages!
  end

  private

  def mark_past_incomplete_as_missed!
    # Mark quotas before from_date as missed if incomplete
    @goal.daily_quotas.where("date < ?", @from_date).incomplete.find_each do |quota|
      quota.update!(status: :missed)
    end
  end

  def redistribute_remaining_pages!
    # Calculate pages still needed based on current book progress
    pages_remaining = @book.total_pages - @book.current_page

    # Get quotas from the specified date onwards
    future_quotas = @goal.daily_quotas.where("date >= ?", @from_date).order(:date)

    return if future_quotas.empty? || pages_remaining <= 0

    # Distribute evenly: base pages per day, with remainder spread across first N days
    num_days = future_quotas.size
    base_pages = pages_remaining / num_days
    extra_days = pages_remaining % num_days

    future_quotas.each_with_index do |quota, i|
      pages_today = base_pages + (i < extra_days ? 1 : 0)

      if pages_today <= 0
        quota.update!(status: :completed) unless quota.completed?
      elsif quota.target_pages != pages_today
        quota.update!(
          target_pages: pages_today,
          status: quota.actual_pages >= pages_today ? :completed : :adjusted
        )
      end
    end
  end
end
