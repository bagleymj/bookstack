class ReadingGoal < ApplicationRecord
  belongs_to :user
  belongs_to :book
  has_many :daily_quotas, dependent: :destroy

  SNAP_PERIOD_LABELS = {
    2 => "Weekend read", 7 => "1-week read", 14 => "2-week read"
  }.freeze

  # Enums
  enum :status, {
    active: 0,
    completed: 1,
    abandoned: 2,
    queued: 3
  }

  # Validations
  validates :target_completion_date, presence: true, unless: :queued?
  validates :started_on, presence: true, unless: :queued?
  validate :target_date_after_start_date, unless: :queued?
  validate :one_active_goal_per_book, on: :create

  # Scopes
  scope :current, -> { active.where("target_completion_date >= ?", Date.current) }
  scope :pipeline_visible, -> { where(status: [:active, :completed, :queued]).or(where("started_on > ?", Date.current)) }
  scope :ordered_by_start, -> { order(:started_on, :target_completion_date) }
  scope :in_reading_list, -> { where(status: [:active, :queued]).where.not(position: nil).order(:position) }

  # Callbacks
  after_create :generate_daily_quotas, unless: :queued?

  def remaining_pages
    book.remaining_pages
  end

  def days_remaining
    reading_days_remaining
  end

  def reading_days_remaining
    return 0 if queued?
    return 0 if target_completion_date < Date.current

    (Date.current..target_completion_date).count do |date|
      user.includes_weekends? || !date.on_weekend?
    end
  end

  # Total reading days across the full goal span (start to end)
  def goal_reading_days
    return 0 if queued? || started_on.nil? || target_completion_date.nil?
    days = (started_on..target_completion_date).count do |date|
      user.includes_weekends? || !date.on_weekend?
    end
    [days, 1].max
  end

  def pages_per_day
    return 0 if reading_days_remaining.zero?
    (remaining_pages.to_f / reading_days_remaining).ceil
  end

  # Calculate minutes per day based on actual daily quotas
  # Uses average of remaining quotas' target pages converted to time
  def calculated_minutes_per_day
    # For completed goals or books with no remaining pages, use all quotas
    # (historical data) since there are no future quotas to calculate from
    quotas = if completed? || book.remaining_pages.zero?
              daily_quotas.where.not(status: :missed)
            else
              daily_quotas.where("date >= ?", Date.current)
                          .where.not(status: :missed)
            end

    return fallback_minutes_per_day if quotas.empty?

    # Calculate average target pages across relevant days
    avg_pages = quotas.average(:target_pages).to_f
    return fallback_minutes_per_day if avg_pages.zero?

    # Convert pages to minutes using book's effective WPM
    wpm = book.actual_wpm || (user.effective_reading_speed * book.difficulty_modifier)
    return fallback_minutes_per_day if wpm.zero?

    words = avg_pages * book.effective_words_per_page
    (words / wpm).ceil
  end

  def today_quota
    daily_quotas.where.not(status: :missed).find_by(date: Date.current)
  end

  def not_started?
    active? && started_on > Date.current
  end

  def on_track?
    return true if completed?
    return false if abandoned?
    return false if not_started?

    quota = today_quota
    return true unless quota

    quota.effectively_complete?
  end

  # Three-state tracking: :behind, :reading_due, :caught_up
  # - caught_up: today's quota is complete (or book position already at target)
  # - reading_due: today's quota exists but isn't done yet
  # - behind: today's quota not done AND has past quotas that weren't completed or missed
  def tracking_status
    return :caught_up if completed?
    return :behind if abandoned?
    return nil if not_started?

    quota = today_quota

    # No quota today (weekend, past end date, missed/redistributed, etc.)
    return :caught_up unless quota

    # Today's quota is effectively done - you're caught up
    return :caught_up if quota.effectively_complete?

    # Today's quota not done - check if also behind from past days
    # Only count quotas that are pending/adjusted (not completed, not missed)
    has_past_pending = daily_quotas.past.where(status: [:pending, :adjusted]).exists?
    has_past_pending ? :behind : :reading_due
  end

  def progress_percentage
    return 100 if completed?
    book.progress_percentage
  end

  def catch_up!
    missed_quotas = daily_quotas.past.incomplete
    return if missed_quotas.empty?

    total_caught_up = 0
    missed_quotas.find_each do |quota|
      pages_to_credit = quota.target_pages - quota.actual_pages
      quota.update!(actual_pages: quota.target_pages, status: :completed)
      total_caught_up += pages_to_credit
    end

    if total_caught_up > 0
      new_page = book.current_page + total_caught_up
      book.update_progress!(new_page)
    end

    redistribute_quotas!
  end

  # Detect discrepancy from yesterday's reading
  # Returns hash with :type (:behind or :ahead), :pages, and :quota
  # Returns nil if no discrepancy or goal not active
  def yesterday_discrepancy
    return nil unless active?
    return nil if started_on > Date.yesterday # Goal hadn't started yet

    yesterday_quota = daily_quotas.find_by(date: Date.yesterday)
    return nil unless yesterday_quota
    return nil if yesterday_quota.missed? # Already handled

    difference = yesterday_quota.actual_pages - yesterday_quota.target_pages

    if difference < 0
      # Behind: didn't read enough
      { type: :behind, pages: difference.abs, quota: yesterday_quota }
    elsif difference > 0
      # Ahead: read more than planned
      { type: :ahead, pages: difference, quota: yesterday_quota }
    else
      nil # Exactly on track
    end
  end

  # Check if there's an unresolved discrepancy that needs user attention
  def has_unresolved_discrepancy?
    discrepancy = yesterday_discrepancy
    return false unless discrepancy

    # Check if we've already acknowledged this discrepancy
    return false if discrepancy_acknowledged_on == Date.current

    true
  end

  # Resolve discrepancy with chosen strategy
  # strategy: :redistribute or :apply_to_today
  def resolve_discrepancy!(strategy)
    discrepancy = yesterday_discrepancy
    return unless discrepancy

    case strategy.to_sym
    when :redistribute
      resolve_discrepancy_redistribute!(discrepancy)
    when :apply_to_today
      resolve_discrepancy_apply_to_today!(discrepancy)
    end

    # Mark as acknowledged
    update!(discrepancy_acknowledged_on: Date.current)
  end

  def redistribute_quotas!(from_date: Date.current)
    QuotaRedistributor.new(self, from_date: from_date).redistribute!
  end

  def mark_completed!
    update!(status: :completed)
    ReadingListScheduler.new(user).schedule! if auto_scheduled?
  end

  def mark_abandoned!
    update!(status: :abandoned)
    ReadingListScheduler.new(user).schedule! if auto_scheduled?
  end

  def reschedule!(new_start, new_end)
    update!(started_on: new_start, target_completion_date: new_end)
    daily_quotas.destroy_all
    daily_quotas.reload  # Clear association cache
    QuotaCalculator.new(self).generate_quotas!
  end

  # Postpone remaining work while preserving past activity
  # - Keeps started_on anchored at earliest activity
  # - Extends target_completion_date
  # - Preserves past quotas, regenerates future quotas starting from new_future_start
  def postpone_remaining!(new_future_start, new_end)
    new_future_start = new_future_start.to_date
    new_end = new_end.to_date

    # Anchor start date at the earliest of: current start, earliest session, or today
    session_bounds = reading_session_boundaries
    anchor_date = started_on
    if session_bounds[:has_sessions] && session_bounds[:earliest] < anchor_date
      anchor_date = session_bounds[:earliest]
    end

    # Delete only future quotas (from today onward)
    daily_quotas.where("date >= ?", Date.current).destroy_all

    # Update the goal's date range
    update!(
      started_on: anchor_date,
      target_completion_date: new_end
    )

    # Generate new quotas only for the future portion
    daily_quotas.reload
    QuotaCalculator.new(self).generate_quotas!(from_date: new_future_start)
  end

  def as_pipeline_data
    return queued_pipeline_data if queued?

    goal_duration = goal_reading_days
    session_boundaries = reading_session_boundaries

    # Use the earlier of started_on or earliest session date as the visual
    # start so that pre-postponement reading still appears in the pipeline
    visual_start = started_on
    if session_boundaries[:earliest] && session_boundaries[:earliest] < started_on
      visual_start = session_boundaries[:earliest]
    end

    {
      id: id,
      book_id: book.id,
      title: book.title,
      author: book.author,
      start_date: visual_start.to_s,
      end_date: target_completion_date.to_s,
      progress: progress_percentage,
      status: book.status,
      difficulty: book.difficulty,
      total_pages: book.total_pages,
      estimated_hours: book.estimated_reading_time_hours,
      estimated_minutes: book.effective_reading_time_minutes,
      minutes_per_day: calculated_minutes_per_day,
      duration_days: goal_reading_days,
      days_remaining: reading_days_remaining,
      calendar_days: (started_on..target_completion_date).count,
      goal_status: status,
      on_track: on_track?,
      pages_per_day: pages_per_day,
      uses_actual_data: book.actual_wpm.present?,
      actual_minutes_by_date: actual_reading_minutes_by_date,
      today_actual_minutes: today_reading_minutes,
      today_remaining_minutes: today_remaining_estimate,
      has_sessions: session_boundaries[:has_sessions],
      earliest_session_date: session_boundaries[:earliest]&.to_s,
      latest_session_date: session_boundaries[:latest]&.to_s,
      session_count: session_boundaries[:count],
      position: position,
      auto_scheduled: auto_scheduled,
      snap_label: snap_period_label
    }
  end

  def has_reading_sessions?
    book.reading_sessions.completed.exists?
  end

  def snap_period_label
    return nil unless started_on && target_completion_date
    calendar_days = (target_completion_date - started_on).to_i + 1

    # Exact match first (e.g., 7 → "1-week read")
    return SNAP_PERIOD_LABELS[calendar_days] if SNAP_PERIOD_LABELS.key?(calendar_days)

    # Calendar-month-aware labels: check if duration aligns with whole months
    month_label = calendar_month_label(calendar_days)
    return month_label if month_label

    # Generate a label for non-standard durations
    if calendar_days <= 4
      "#{calendar_days}-day read"
    elsif calendar_days <= 13
      weeks = (calendar_days / 7.0).round(1)
      weeks == weeks.to_i ? "#{weeks.to_i}-week read" : "#{weeks}-week read"
    elsif calendar_days <= 60
      weeks = (calendar_days / 7.0).round
      "#{weeks}-week read"
    else
      months = (calendar_days / 30.0).round(1)
      months == months.to_i ? "#{months.to_i}-month read" : "#{months}-month read"
    end
  end

  # Detect if a duration corresponds to a whole number of calendar months.
  # Calendar months vary (28-31 days), so we check if started_on + N months
  # lands on the day after target_completion_date.
  def calendar_month_label(calendar_days)
    return nil if calendar_days < 28

    [1, 2, 3, 6].each do |n|
      expected_end = (started_on + n.months) - 1
      if expected_end == target_completion_date
        return "#{n}-month read"
      end
    end

    nil
  end

  # Returns boundaries of all reading sessions for this book up to the goal's end date.
  # Includes sessions before started_on so that pre-postponement reading is captured.
  def reading_session_boundaries
    return { has_sessions: false, earliest: nil, latest: nil, count: 0 } if target_completion_date.nil?

    sessions = book.reading_sessions
                   .completed
                   .where("started_at <= ?", target_completion_date.end_of_day)

    return { has_sessions: false, earliest: nil, latest: nil, count: 0 } if sessions.empty?

    dates = sessions.pluck(:started_at).map(&:to_date)
    {
      has_sessions: true,
      earliest: dates.min,
      latest: dates.max,
      count: sessions.count
    }
  end

  # Returns minutes read today for this goal's book
  def today_reading_minutes
    sessions = book.reading_sessions
                   .completed
                   .where(started_at: Date.current.beginning_of_day..Date.current.end_of_day)

    sessions.sum { |s| s.effective_duration_minutes }
  end

  # Returns estimated minutes remaining for today's quota
  def today_remaining_estimate
    quota = today_quota
    return 0 unless quota
    quota.estimated_minutes_remaining
  end

  # Returns hash of date string -> minutes read for past days up to the goal's end date.
  # Includes sessions before started_on so that pre-postponement reading is captured.
  def actual_reading_minutes_by_date
    # Only include dates up to yesterday (today is not yet complete)
    end_date = [target_completion_date, Date.current - 1].min

    # Get all completed reading sessions for this book up to the end date
    sessions = book.reading_sessions
                   .completed
                   .where("started_at <= ?", end_date.end_of_day)

    return {} if sessions.empty?

    # Group by date and sum effective duration
    sessions.each_with_object({}) do |session, hash|
      date_key = session.started_at.to_date.to_s
      hash[date_key] ||= 0
      hash[date_key] += session.effective_duration_minutes
    end
  end

  private

  def queued_pipeline_data
    {
      id: id,
      book_id: book.id,
      title: book.title,
      author: book.author,
      start_date: nil,
      end_date: nil,
      progress: book.progress_percentage,
      status: book.status,
      difficulty: book.difficulty,
      total_pages: book.total_pages,
      estimated_hours: book.estimated_reading_time_hours,
      estimated_minutes: book.effective_reading_time_minutes,
      minutes_per_day: 0,
      duration_days: 0,
      days_remaining: 0,
      calendar_days: 0,
      goal_status: status,
      on_track: false,
      pages_per_day: 0,
      uses_actual_data: false,
      actual_minutes_by_date: {},
      today_actual_minutes: 0,
      today_remaining_minutes: 0,
      has_sessions: false,
      earliest_session_date: nil,
      latest_session_date: nil,
      session_count: 0,
      position: position,
      auto_scheduled: auto_scheduled
    }
  end

  def resolve_discrepancy_redistribute!(discrepancy)
    if discrepancy[:type] == :behind
      # Mark yesterday as missed, redistribute remaining pages
      discrepancy[:quota].update!(status: :missed) unless discrepancy[:quota].completed?
      redistribute_quotas!
    else
      # Ahead: redistribute the gains across remaining days
      redistribute_quotas!
    end
  end

  def resolve_discrepancy_apply_to_today!(discrepancy)
    today = today_quota
    return unless today

    if discrepancy[:type] == :behind
      # Behind: add missed pages to today's target
      # User must catch up fully today
      new_target = today.target_pages + discrepancy[:pages]
      today.update!(target_pages: new_target, status: :adjusted)

      # Mark yesterday as missed
      discrepancy[:quota].update!(status: :missed) unless discrepancy[:quota].completed?
    else
      # Ahead: credit extra pages to today
      # Reduce effective target by extra pages read
      credited_pages = [discrepancy[:pages], today.target_pages].min
      today.update!(actual_pages: today.actual_pages + credited_pages)

      # If credited pages cover today's quota, mark complete
      if today.actual_pages >= today.target_pages
        today.update!(status: :completed)
      end
    end
  end

  def fallback_minutes_per_day
    goal_duration = goal_reading_days
    return 0 if goal_duration.zero?

    # For finished books, effective_reading_time_minutes is 0 (no remaining pages),
    # so use total words to compute the reading time the goal originally represented
    reading_minutes = if book.remaining_pages.zero?
                        wpm = book.actual_wpm || (user.effective_reading_speed * book.difficulty_modifier)
                        return 0 if wpm.zero?
                        book.total_words.to_f / wpm
                      else
                        book.effective_reading_time_minutes.to_f
                      end

    (reading_minutes / goal_duration).ceil
  end

  def generate_daily_quotas
    QuotaCalculator.new(self).generate_quotas!
  end

  def target_date_after_start_date
    return unless target_completion_date && started_on
    if target_completion_date <= started_on
      errors.add(:target_completion_date, "must be after start date")
    end
  end

  def one_active_goal_per_book
    if user.reading_goals.where(status: [:active, :queued]).where(book: book).exists?
      errors.add(:book, "already has an active or queued reading goal")
    end
  end
end
