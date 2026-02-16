class DailyQuota < ApplicationRecord
  self.table_name = "daily_quotas"

  belongs_to :reading_goal

  # Enums
  enum :status, {
    pending: 0,
    completed: 1,
    missed: 2,
    adjusted: 3
  }

  # Validations
  validates :date, presence: true
  validates :target_pages, presence: true, numericality: { greater_than: 0 }
  validates :actual_pages, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :for_date, ->(date) { where(date: date) }
  scope :past, -> { where("date < ?", Date.current) }
  scope :future, -> { where("date > ?", Date.current) }
  scope :today, -> { where(date: Date.current) }
  scope :incomplete, -> { where.not(status: :completed) }

  def book
    reading_goal.book
  end

  def user
    reading_goal.user
  end

  def pages_remaining
    [target_pages - actual_pages, 0].max
  end

  def percentage_complete
    return 100 if effectively_complete?
    return 0 if target_pages.zero?
    [(actual_pages.to_f / target_pages * 100).round, 100].min
  end

  # Returns true if the quota is complete - either by status or because
  # the book's current position has reached the target
  def effectively_complete?
    return true if completed?
    return true if book.actual_current_page >= target_page_number
    false
  end

  # The last page number to read to complete this quota
  def target_page_number
    # Get today's quota to determine pages already read today
    today_quota = reading_goal.daily_quotas.where.not(status: :missed).find_by(date: Date.current)

    # Calculate start-of-day position (actual_current_page is now "page you're on")
    start_of_day = book.actual_current_page
    start_of_day -= today_quota.actual_pages if today_quota

    # Sum target pages from today through this quota's date
    cumulative_pages = reading_goal.daily_quotas
                                   .where(date: Date.current..date)
                                   .where.not(status: :missed)
                                   .sum(:target_pages)

    start_of_day + cumulative_pages
  end

  # Estimated minutes to complete remaining pages for this quota
  def estimated_minutes_remaining
    return 0 if effectively_complete?

    remaining = pages_remaining
    return 0 if remaining <= 0

    wpm = book.actual_wpm || (user.effective_reading_speed * book.difficulty_modifier)
    return 0 if wpm.zero?

    words_remaining = remaining * book.effective_words_per_page
    (words_remaining / wpm).ceil
  end

  def record_pages!(pages_read)
    new_actual = actual_pages + pages_read
    new_status = new_actual >= target_pages ? :completed : status

    update!(
      actual_pages: new_actual,
      status: new_status
    )
  end

  def mark_missed!
    return if completed?
    return if date >= Date.current

    update!(status: :missed)
    reading_goal.redistribute_quotas!
  end
end
