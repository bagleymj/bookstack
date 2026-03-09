class ReadingListScheduler
  TIERS = [:week, :two_weeks, :three_weeks, :four_weeks, :six_weeks,
           :twelve_weeks, :twenty_six_weeks, :fifty_two_weeks].freeze
  TIER_WEEKS = {
    week: 1, two_weeks: 2, three_weeks: 3, four_weeks: 4, six_weeks: 6,
    twelve_weeks: 12, twenty_six_weeks: 26, fifty_two_weeks: 52
  }.freeze
  MAX_ADJUSTMENT_ITERATIONS = 5
  PLACEMENT_HORIZON_WEEKS = 104

  attr_reader :target_budget, :deficit

  def initialize(user)
    @user = user
  end

  def metrics
    return default_metrics unless throughput_pace?

    measure_actuals!
    budget = compute_target_budget
    target = annual_pace.round

    pace_window_end = @pace_start + 365
    scheduled_completions = @user.reading_goals
      .where(status: [:active, :queued])
      .where.not(target_completion_date: nil)
      .where("target_completion_date <= ?", pace_window_end)
      .count
    projected = @actual_completed + scheduled_completions

    queued_count = @user.reading_goals.where(status: :queued, auto_scheduled: true).count

    {
      pace_status: pace_status_label(target),
      deficit: @deficit.round(1),
      derived_budget: budget.round,
      projected_completions: projected,
      pace_target: target,
      queue_depth: queued_count,
      queue_warning: queue_warning(queued_count, target, projected)
    }
  end

  def schedule!
    return unless throughput_pace?

    # Phase 1: Measure actuals
    measure_actuals!

    # Phase 2: Compute derived daily budget
    @target_budget = compute_target_budget
    return if @target_budget <= 0
    compute_weekend_budgets

    # Phase 3: Level-load tier assignment
    @load_profile = Hash.new(0.0)
    @concurrent_count = Hash.new(0)

    locked_goals.each { |goal| add_goal_to_profiles(goal) }

    @placements = []
    gather_schedulable_goals.each do |goal|
      book_minutes = estimate_remaining_minutes(goal.book)
      placement = find_leveled_placement(book_minutes)
      next unless placement

      apply_placement!(goal, placement)
      add_placement_to_profiles(placement)
      @placements << { goal: goal, placement: placement, tier: placement[:tier], book_minutes: book_minutes }
    end

    # Phase 4: Verify throughput
    verify_throughput!

    # Phase 5: Generate quotas
    @placements.each { |entry| generate_quotas_for!(entry[:goal]) }
  end

  private

  # ─── Phase 1 ────────────────────────────────────────────────────

  def measure_actuals!
    @pace_start = @user.reading_pace_set_on || Date.current.beginning_of_year
    @days_elapsed = [(Date.current - @pace_start).to_i, 1].max
    @days_remaining = [365 - (Date.current - @pace_start).to_i, 1].max
    @actual_completed = count_completed_since(@pace_start)
    @deficit = (annual_pace * @days_elapsed / 365.0) - @actual_completed
  end

  def count_completed_since(date)
    @user.books
         .where(status: :completed)
         .where("completed_at >= ?", date.beginning_of_day)
         .count
  end

  # ─── Phase 2 ────────────────────────────────────────────────────

  def compute_target_budget
    books_remaining = [annual_pace - @actual_completed, 0].max
    return 0 if books_remaining <= 0

    window = build_budget_window([annual_pace.round, 1].max)
    return 0 if window.empty?

    avg_minutes = window.sum { |book| full_book_minutes(book) }.to_f / window.size
    (books_remaining * avg_minutes) / @days_remaining
  end

  def build_budget_window(window_size)
    list_books = @user.reading_goals
                      .where(auto_scheduled: true)
                      .where.not(position: nil)
                      .where(status: [:queued, :active])
                      .includes(:book)
                      .order(:position)
                      .limit(window_size)
                      .map(&:book)

    return list_books if list_books.size >= window_size

    remaining_slots = window_size - list_books.size
    exclude_ids = list_books.map(&:id)
    completed = @user.books
                     .where(status: :completed)
                     .where.not(id: exclude_ids)
                     .order(completed_at: :desc)
                     .limit(remaining_slots)
                     .to_a

    list_books + completed
  end

  def full_book_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60 if wpm.zero?
    (book.total_words.to_f / wpm).ceil
  end

  def compute_weekend_budgets
    weekly_total = @target_budget * 7
    case @user.weekend_mode
    when "skip"
      @weekday_budget = weekly_total / 5.0
      @weekend_budget = 0.0
    when "same"
      @weekday_budget = @weekend_budget = weekly_total / 7.0
    when "capped"
      @weekend_budget = @user.weekend_reading_minutes.to_f
      @weekday_budget = [(weekly_total - @weekend_budget * 2) / 5.0, 0.0].max
    end
  end

  def budget_for_date(date)
    date.on_weekend? ? @weekend_budget : @weekday_budget
  end

  # ─── Phase 3 ────────────────────────────────────────────────────

  def find_leveled_placement(book_minutes)
    each_monday do |monday|
      best_at_monday = nil
      best_dev = Float::INFINITY

      TIERS.each do |tier|
        end_date = calendar_end(monday, tier)
        daily_share = compute_weekday_share(book_minutes, monday, end_date)
        next if daily_share <= 0
        next unless fits_concurrency?(monday, end_date)

        max_dev = compute_max_deviation(monday, end_date, daily_share)

        if max_dev < best_dev
          best_dev = max_dev
          best_at_monday = { start: monday, end: end_date, share: daily_share, tier: tier }
        end
      end

      return best_at_monday if best_at_monday
    end

    default_placement(book_minutes)
  end

  def compute_max_deviation(start_date, end_date, daily_share)
    max_dev = 0.0
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      budget = budget_for_date(date)
      next if budget <= 0
      projected = @load_profile[date] + share_for_date(daily_share, date)
      deviation = (projected - budget).abs
      max_dev = deviation if deviation > max_dev
    end
    max_dev
  end

  def compute_weekday_share(book_minutes, start_date, end_date)
    if @user.capped? && @weekday_budget > 0
      ratio = @weekend_budget / @weekday_budget
      weekday_count = (start_date..end_date).count { |d| !d.on_weekend? }
      weekend_count = (start_date..end_date).count { |d| d.on_weekend? }
      effective_days = weekday_count + weekend_count * ratio
      effective_days > 0 ? book_minutes.to_f / effective_days : 0
    else
      reading_days = count_reading_days(start_date, end_date)
      reading_days > 0 ? book_minutes.to_f / reading_days : 0
    end
  end

  def share_for_date(share, date)
    return share unless @user.capped? && date.on_weekend? && @weekday_budget > 0
    share * (@weekend_budget / @weekday_budget)
  end

  def fits_concurrency?(start_date, end_date)
    limit = effective_concurrency_limit
    return true unless limit
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      return false if @concurrent_count[date] >= limit
    end
    true
  end

  def each_monday
    monday = snap_to_monday(Date.current)
    PLACEMENT_HORIZON_WEEKS.times do
      yield monday
      monday += 7
    end
  end

  def apply_placement!(goal, placement)
    goal.update!(
      started_on: placement[:start],
      target_completion_date: placement[:end],
      status: :active
    )
  end

  def add_goal_to_profiles(goal)
    return unless goal.started_on && goal.target_completion_date
    start = [goal.started_on, Date.current].max
    book_minutes = estimate_remaining_minutes(goal.book)
    daily_share = compute_weekday_share(book_minutes, start, goal.target_completion_date)
    return if daily_share <= 0
    add_range_to_profiles(start, goal.target_completion_date, daily_share)
  end

  def add_placement_to_profiles(placement)
    add_range_to_profiles(placement[:start], placement[:end], placement[:share])
  end

  def add_range_to_profiles(start_date, end_date, daily_share)
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      @load_profile[date] += share_for_date(daily_share, date)
      @concurrent_count[date] += 1
    end
  end

  def remove_range_from_profiles(start_date, end_date, daily_share)
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      @load_profile[date] -= share_for_date(daily_share, date)
      @concurrent_count[date] -= 1
    end
  end

  def default_placement(book_minutes)
    start = snap_to_monday(Date.current)
    tier = TIERS.last
    end_date = calendar_end(start, tier)
    share = compute_weekday_share(book_minutes, start, end_date)
    { start: start, end: end_date, share: share, tier: tier }
  end

  # ─── Phase 4 ────────────────────────────────────────────────────

  def verify_throughput!
    target = annual_pace.round
    tolerance = [2, (target * 0.05).ceil].max

    MAX_ADJUSTMENT_ITERATIONS.times do
      projected = count_projected_completions
      break if projected.between?(target - tolerance, target + tolerance)

      if projected < target - tolerance
        break unless try_shorten_longest_tier!
      else
        break unless try_lengthen_shortest_tier!
      end
    end
  end

  def count_projected_completions
    pace_window_end = @pace_start + 365

    locked_count = locked_goals.count do |g|
      g.target_completion_date && g.target_completion_date <= pace_window_end
    end

    placed_count = @placements.count do |entry|
      entry[:goal].target_completion_date <= pace_window_end
    end

    @actual_completed + locked_count + placed_count
  end

  def try_shorten_longest_tier!
    adjustable = @placements
      .reject { |p| p[:goal].has_reading_sessions? }
      .sort_by { |p| -TIER_WEEKS[p[:tier]] }

    adjustable.each do |entry|
      tier_idx = TIERS.index(entry[:tier])
      next if tier_idx.nil? || tier_idx == 0

      shorter_tier = TIERS[tier_idx - 1]
      goal = entry[:goal]
      new_end = calendar_end(goal.started_on, shorter_tier)
      new_share = compute_weekday_share(entry[:book_minutes], goal.started_on, new_end)
      next if new_share <= 0
      next unless fits_concurrency_for_adjustment?(goal.started_on, new_end, entry)

      remove_range_from_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])
      goal.update!(target_completion_date: new_end)
      new_placement = { start: goal.started_on, end: new_end, share: new_share, tier: shorter_tier }
      add_range_to_profiles(goal.started_on, new_end, new_share)

      entry[:tier] = shorter_tier
      entry[:placement] = new_placement
      return true
    end

    false
  end

  def try_lengthen_shortest_tier!
    adjustable = @placements
      .reject { |p| p[:goal].has_reading_sessions? }
      .sort_by { |p| TIER_WEEKS[p[:tier]] }

    adjustable.each do |entry|
      tier_idx = TIERS.index(entry[:tier])
      next if tier_idx.nil? || tier_idx >= TIERS.length - 1

      longer_tier = TIERS[tier_idx + 1]
      goal = entry[:goal]
      new_end = calendar_end(goal.started_on, longer_tier)
      new_share = compute_weekday_share(entry[:book_minutes], goal.started_on, new_end)
      next if new_share <= 0

      remove_range_from_profiles(goal.started_on, goal.target_completion_date, entry[:placement][:share])
      goal.update!(target_completion_date: new_end)
      new_placement = { start: goal.started_on, end: new_end, share: new_share, tier: longer_tier }
      add_range_to_profiles(goal.started_on, new_end, new_share)

      entry[:tier] = longer_tier
      entry[:placement] = new_placement
      return true
    end

    false
  end

  # Concurrency check that excludes the entry being adjusted (it's temporarily removed)
  def fits_concurrency_for_adjustment?(start_date, end_date, excluded_entry)
    limit = effective_concurrency_limit
    return true unless limit
    (start_date..end_date).each do |date|
      next unless reading_day?(date)
      # The excluded entry was already removed from profiles, so current count is accurate
      return false if @concurrent_count[date] >= limit
    end
    true
  end

  # ─── Phase 5 ────────────────────────────────────────────────────

  def generate_quotas_for!(goal)
    goal.daily_quotas.destroy_all
    goal.daily_quotas.reload
    ProfileAwareQuotaCalculator.new(goal, @user).generate_quotas!
  end

  # ─── Timeline & Goals ──────────────────────────────────────────

  def locked_goals
    @locked_goals ||= @user.reading_goals
                            .active
                            .where.not(target_completion_date: nil)
                            .includes(:book)
                            .select(&:has_reading_sessions?)
  end

  def gather_schedulable_goals
    @user.reading_goals
         .where(status: [:queued, :active])
         .where(auto_scheduled: true)
         .where.not(position: nil)
         .includes(:book)
         .order(:position)
         .reject { |g| g.active? && g.has_reading_sessions? }
  end

  # ─── Calendar Helpers ──────────────────────────────────────────

  def snap_to_monday(date)
    return date if date.monday?
    date + ((1 - date.wday) % 7)
  end

  def calendar_end(start_date, tier)
    start_date + (TIER_WEEKS[tier] * 7) - 1
  end

  def count_reading_days(start_date, end_date)
    return 0 if start_date.nil? || end_date.nil?
    if @user.includes_weekends?
      (end_date - start_date).to_i + 1
    else
      (start_date..end_date).count { |d| !d.on_weekend? }
    end
  end

  def reading_day?(date)
    @user.includes_weekends? || !date.on_weekend?
  end

  # ─── Estimates ─────────────────────────────────────────────────

  def estimate_remaining_minutes(book)
    wpm = book.actual_wpm || (@user.effective_reading_speed * book.difficulty_modifier)
    return 60 if wpm.zero?
    (book.remaining_words.to_f / wpm).ceil
  end

  def annual_pace
    return 0 unless @user.reading_pace_value&.positive?
    case @user.reading_pace_type
    when "books_per_year"  then @user.reading_pace_value.to_f
    when "books_per_month" then @user.reading_pace_value * 12.0
    when "books_per_week"  then @user.reading_pace_value * 52.0
    else 0
    end
  end

  def throughput_pace?
    %w[books_per_year books_per_month books_per_week].include?(@user.reading_pace_type) &&
      @user.reading_pace_value&.positive?
  end

  def effective_concurrency_limit
    @user.concurrency_limit || @user.max_concurrent_books
  end

  # ─── Metrics Helpers ────────────────────────────────────────────

  def default_metrics
    { pace_status: nil, deficit: 0, derived_budget: 0,
      projected_completions: 0, pace_target: 0, queue_depth: 0, queue_warning: nil }
  end

  def pace_status_label(target)
    return "on pace" if @deficit.abs < 0.5
    behind = @deficit.round
    if behind > 0
      "#{behind} #{'book'.pluralize(behind)} behind"
    else
      "#{behind.abs} #{'book'.pluralize(behind.abs)} ahead"
    end
  end

  def queue_warning(queued_count, target, projected)
    shortfall = target - projected
    return nil if shortfall <= 0
    "Add #{shortfall}+ books to maintain your pace"
  end
end
