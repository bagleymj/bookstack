class DailyReflow
  SPIKE_TOLERANCE = 1.1  # Allow 10% over derived budget before promoting
  MAX_EXTENSIONS = 5     # Safety cap on extensions per reflow cycle

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
    goals = active_goals.to_a

    goals.each { |goal| mark_missed_quotas(goal) }
    promoted_ids = promote_spiking_goals!(goals)
    goals.each { |goal| redistribute_remaining(goal) unless promoted_ids.include?(goal.id) }

    @user.update_column(:quotas_generated_on, Date.current)
  end

  private

  def active_goals
    @user.reading_goals
         .active
         .where("target_completion_date >= ?", Date.current)
         .includes(:book)
  end

  def mark_missed_quotas(goal)
    DailyQuota.where(reading_goal_id: goal.id)
              .where("date < ?", Date.current)
              .where(status: [:pending, :adjusted])
              .update_all(status: DailyQuota.statuses[:missed])
  end

  # Redistribute remaining pages across remaining days in the current tier.
  # Only adjusts future quotas — past quotas are left as-is (completed or missed).
  def redistribute_remaining(goal)
    remaining_pages = goal.book.remaining_pages
    return if remaining_pages <= 0

    future_quotas = DailyQuota.where(reading_goal_id: goal.id)
                              .where("date >= ?", Date.current)
                              .where.not(status: :missed)
                              .order(:date)

    return if future_quotas.empty?

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

  # ─── Tier Promotion ─────────────────────────────────────────

  # When the total daily reading load exceeds the derived budget, extend the
  # heaviest goal by one week. This prevents spikes caused by books taking
  # longer than estimated (e.g., slower actual_wpm than predicted).
  def promote_spiking_goals!(goals)
    promoted = Set.new
    return promoted unless heijunka_mode?

    budget = derived_daily_budget
    return promoted unless budget&.positive?

    MAX_EXTENSIONS.times do
      goal_shares = goals.filter_map do |goal|
        share = daily_share_minutes(goal)
        [goal, share] if share > 0
      end
      break if goal_shares.empty?

      total_load = goal_shares.sum { |_, share| share }
      break if total_load <= budget * SPIKE_TOLERANCE

      heaviest_goal, _ = goal_shares.max_by { |_, share| share }
      break unless extend_by_one_week(heaviest_goal)

      promoted << heaviest_goal.id
    end

    promoted
  end

  def daily_share_minutes(goal)
    remaining_minutes = estimate_remaining_minutes(goal.book)
    remaining_days = count_remaining_reading_days(goal)
    return 0.0 if remaining_days <= 0
    remaining_minutes.to_f / remaining_days
  end

  def estimate_remaining_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60.0 if wpm.zero?
    book.remaining_words.to_f / wpm
  end

  def count_remaining_reading_days(goal)
    end_date = goal.target_completion_date
    return 0 if end_date.nil? || end_date < Date.current
    if @user.includes_weekends?
      (end_date - Date.current).to_i + 1
    else
      (Date.current..end_date).count { |d| !d.on_weekend? }
    end
  end

  def extend_by_one_week(goal)
    new_end = goal.target_completion_date + 7
    return false if new_end > Date.current + 730  # 2-year safety cap

    goal.update!(target_completion_date: new_end)

    # Regenerate future quotas across the extended range
    DailyQuota.where(reading_goal_id: goal.id)
              .where("date >= ?", Date.current)
              .delete_all
    ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!(from_date: Date.current)

    true
  end

  def derived_daily_budget
    ReadingListScheduler.new(@user).metrics[:derived_budget]
  end

  def heijunka_mode?
    %w[books_per_year books_per_month books_per_week].include?(@user.reading_pace_type) &&
      @user.reading_pace_value&.positive?
  end
end
