class ReadingGoal < ApplicationRecord
  belongs_to :user
  belongs_to :book
  has_many :daily_quotas, dependent: :destroy

  # Enums
  enum :status, {
    active: 0,
    completed: 1,
    abandoned: 2
  }

  # Validations
  validates :target_completion_date, presence: true
  validates :started_on, presence: true
  validate :target_date_after_start_date
  validate :one_active_goal_per_book, on: :create

  # Scopes
  scope :current, -> { active.where("target_completion_date >= ?", Date.current) }

  # Callbacks
  after_create :generate_daily_quotas

  def remaining_pages
    book.remaining_pages
  end

  def days_remaining
    return 0 if target_completion_date < Date.current
    (target_completion_date - Date.current).to_i
  end

  def reading_days_remaining
    return 0 if target_completion_date < Date.current

    (Date.current..target_completion_date).count do |date|
      include_weekends? || !date.on_weekend?
    end
  end

  def pages_per_day
    return 0 if reading_days_remaining.zero?
    (remaining_pages.to_f / reading_days_remaining).ceil
  end

  def today_quota
    daily_quotas.find_by(date: Date.current)
  end

  def on_track?
    return true if completed?
    return false if abandoned?

    quota = today_quota
    return true unless quota

    quota.completed? || quota.actual_pages >= quota.target_pages
  end

  def progress_percentage
    return 100 if completed?
    book.progress_percentage
  end

  def redistribute_quotas!
    QuotaRedistributor.new(self).redistribute!
  end

  def mark_completed!
    update!(status: :completed)
  end

  def mark_abandoned!
    update!(status: :abandoned)
  end

  private

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
    if user.reading_goals.active.where(book: book).exists?
      errors.add(:book, "already has an active reading goal")
    end
  end
end
