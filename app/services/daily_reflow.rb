class DailyReflow
  def initialize(user)
    @user = user
  end

  def reflow_if_stale!
    return unless needs_reflow?
    reflow!
  end

  def needs_reflow?
    @user.quotas_generated_on.nil? || @user.quotas_generated_on < Date.current
  end

  def reflow!
    active_goals.each do |goal|
      redistribute_remaining(goal)
    end

    @user.update_column(:quotas_generated_on, Date.current)
  end

  private

  def active_goals
    @user.reading_goals
         .active
         .where("target_completion_date >= ?", Date.current)
         .includes(:book)
  end

  # Redistribute remaining pages across remaining days in the current tier.
  # Only adjusts future quotas — past quotas are left as-is (completed or missed).
  def redistribute_remaining(goal)
    remaining_pages = goal.book.remaining_pages
    return if remaining_pages <= 0

    # Mark past incomplete quotas as missed (query DailyQuota directly to avoid association cache)
    DailyQuota.where(reading_goal_id: goal.id)
              .where("date < ?", Date.current)
              .where(status: [:pending, :adjusted])
              .update_all(status: DailyQuota.statuses[:missed])

    # Get future quotas (today onward)
    future_quotas = DailyQuota.where(reading_goal_id: goal.id)
                              .where("date >= ?", Date.current)
                              .where.not(status: :missed)
                              .order(:date)

    return if future_quotas.empty?

    # Distribute remaining pages across future quotas
    num_days = future_quotas.count
    base_pages = remaining_pages / num_days
    remainder = remaining_pages % num_days

    future_quotas.each_with_index do |quota, i|
      new_target = base_pages + (i < remainder ? 1 : 0)
      quota.update_columns(
        target_pages: new_target,
        status: DailyQuota.statuses[:pending]
      )
    end
  end
end
