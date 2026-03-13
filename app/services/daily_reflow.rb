class DailyReflow
  def initialize(user)
    @user = user
    @summary = []
  end

  def reflow_if_stale!
    return [] unless needs_reflow?
    reflow!
  end

  def needs_reflow?
    @user.quotas_generated_on.nil? || @user.quotas_generated_on < Date.current
  end

  def reflow!
    goals = active_goals.to_a

    # Snapshot quotas before changes so we can describe what shifted
    snapshots = snapshot_today_quotas(goals)

    goals.each { |goal| mark_missed_quotas(goal) }

    handled_ids = heijunka_mode? ? ReadingListScheduler.new(@user).schedule! : Set.new

    goals.each do |goal|
      next if handled_ids.include?(goal.id)
      redistribute_remaining(goal)
    end

    @user.update_column(:quotas_generated_on, Date.current)

    # Build human-readable summary by comparing before/after
    build_summary(goals, snapshots)

    @summary
  end

  private

  def active_goals
    @user.reading_goals
         .active
         .where("target_completion_date >= ?", Date.current)
         .includes(:book)
  end

  def mark_missed_quotas(goal)
    missed_count = DailyQuota.where(reading_goal_id: goal.id)
                             .where("date < ?", Date.current)
                             .where(status: [:pending, :adjusted])

    count = missed_count.count
    if count > 0
      missed_count.update_all(status: DailyQuota.statuses[:missed])
      @summary << {
        type: :missed,
        book: goal.book.title,
        days: count
      }
    end
  end

  def redistribute_remaining(goal)
    remaining_pages = goal.book.remaining_pages
    return if remaining_pages <= 0

    cutoff = quota_modification_cutoff
    future_quotas = DailyQuota.where(reading_goal_id: goal.id)
                              .where("date >= ?", cutoff)
                              .where.not(status: :missed)
                              .order(:date)

    return if future_quotas.empty?

    num_days = future_quotas.count
    if cutoff > Date.current
      todays_quota = DailyQuota.find_by(reading_goal_id: goal.id, date: Date.current)
      remaining_pages -= todays_quota.target_pages if todays_quota
      remaining_pages = [remaining_pages, 0].max
    end

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

  def quota_modification_cutoff
    user_has_sessions_today? ? Date.current + 1 : Date.current
  end

  def user_has_sessions_today?
    @user_has_sessions_today ||= ReadingSession
      .where(user: @user)
      .where.not(ended_at: nil)
      .where("started_at >= ?", Date.current.beginning_of_day)
      .exists?
  end

  def heijunka_mode?
    %w[books_per_year books_per_month books_per_week].include?(@user.reading_pace_type) &&
      @user.reading_pace_value&.positive?
  end

  def snapshot_today_quotas(goals)
    snapshots = {}
    goals.each do |goal|
      quota = DailyQuota.find_by(reading_goal_id: goal.id, date: Date.current)
      next unless quota
      snapshots[goal.id] = { target_pages: quota.target_pages, book: goal.book.title }
    end
    snapshots
  end

  def build_summary(goals, snapshots)
    goals.each do |goal|
      old = snapshots[goal.id]
      next unless old

      quota = DailyQuota.find_by(reading_goal_id: goal.id, date: Date.current)
      next unless quota

      new_target = quota.target_pages
      old_target = old[:target_pages]
      diff = new_target - old_target

      next if diff == 0

      @summary << {
        type: :adjusted,
        book: old[:book],
        old_pages: old_target,
        new_pages: new_target,
        direction: diff > 0 ? :up : :down,
        diff: diff.abs
      }
    end
  end
end
