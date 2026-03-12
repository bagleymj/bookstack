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
    pages_remaining = @book.remaining_pages

    # If user has read today, protect today's quota from modification
    effective_from = if @from_date <= Date.current && user_has_sessions_today?
                       Date.current + 1
                     else
                       @from_date
                     end

    future_quotas = @goal.daily_quotas.where("date >= ?", effective_from).order(:date)

    return if future_quotas.empty? || pages_remaining <= 0

    # Subtract today's committed quota from remaining pages if today is protected
    if effective_from > @from_date
      todays_quota = @goal.daily_quotas.find_by(date: Date.current)
      pages_remaining -= todays_quota.target_pages if todays_quota
      pages_remaining = [pages_remaining, 0].max
    end

    return if pages_remaining <= 0

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

  def user_has_sessions_today?
    ReadingSession
      .where(user: @goal.user)
      .where.not(ended_at: nil)
      .where("started_at >= ?", Date.current.beginning_of_day)
      .exists?
  end
end
