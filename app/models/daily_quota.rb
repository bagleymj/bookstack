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
    return 100 if completed?
    return 0 if target_pages.zero?
    [(actual_pages.to_f / target_pages * 100).round, 100].min
  end

  # The actual book page number to reach after completing this quota
  # Current position + cumulative pages from today through this date
  def target_page_number
    cumulative_pages = reading_goal.daily_quotas
                                   .where(date: Date.current..date)
                                   .sum(:target_pages)
    book.actual_current_page + cumulative_pages
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
