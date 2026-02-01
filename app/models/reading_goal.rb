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
  scope :pipeline_visible, -> { where(status: [:active, :completed]).or(where("started_on > ?", Date.current)) }
  scope :ordered_by_start, -> { order(:started_on, :target_completion_date) }

  # Callbacks
  after_create :generate_daily_quotas

  def remaining_pages
    book.remaining_pages
  end

  def days_remaining
    return 0 if target_completion_date < Date.current
    (Date.current..target_completion_date).count
  end

  def reading_days_remaining
    return 0 if target_completion_date < Date.current

    (Date.current..target_completion_date).count do |date|
      include_weekends? || !date.on_weekend?
    end
  end

  # Total reading days across the full goal span (start to end)
  def goal_reading_days
    days = (started_on..target_completion_date).count do |date|
      include_weekends? || !date.on_weekend?
    end
    [days, 1].max
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

  def reschedule!(new_start, new_end)
    update!(started_on: new_start, target_completion_date: new_end)
    daily_quotas.destroy_all
    QuotaCalculator.new(self).generate_quotas!
  end

  def as_pipeline_data
    goal_duration = goal_reading_days
    {
      id: id,
      book_id: book.id,
      title: book.title,
      author: book.author,
      start_date: started_on.to_s,
      end_date: target_completion_date.to_s,
      progress: progress_percentage,
      status: book.status,
      difficulty: book.difficulty,
      total_pages: book.total_pages,
      estimated_hours: book.estimated_reading_time_hours,
      estimated_minutes: book.effective_reading_time_minutes,
      minutes_per_day: (book.effective_reading_time_minutes.to_f / goal_duration).ceil,
      duration_days: (started_on..target_completion_date).count,
      goal_status: status,
      on_track: on_track?,
      pages_per_day: pages_per_day,
      uses_actual_data: book.actual_wpm.present?
    }
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
