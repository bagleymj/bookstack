class Book < ApplicationRecord
  belongs_to :user
  has_many :reading_sessions, dependent: :destroy
  has_many :reading_goals, dependent: :destroy

  # Enums
  enum :status, {
    unread: 0,
    reading: 1,
    completed: 2,
    abandoned: 3
  }

  enum :difficulty, {
    easy: 1,
    below_average: 2,
    average: 3,
    challenging: 4,
    dense: 5
  }, prefix: true

  # Difficulty modifiers for reading speed
  DIFFICULTY_MODIFIERS = {
    easy: 1.3,
    below_average: 1.15,
    average: 1.0,
    challenging: 0.85,
    dense: 0.7
  }.freeze

  # Validations
  validates :title, presence: true
  validates :first_page, presence: true, numericality: { greater_than: 0 }
  validates :last_page, presence: true, numericality: { greater_than: 0 }
  validates :words_per_page, numericality: { greater_than: 0 }, allow_nil: true
  validates :current_page, numericality: { greater_than_or_equal_to: 0 }
  validates :difficulty, inclusion: { in: difficulties.keys }
  validate :last_page_after_first_page

  # Scopes
  scope :in_progress, -> { where(status: :reading) }
  scope :not_started, -> { where(status: :unread) }
  scope :finished, -> { where(status: :completed) }
  scope :by_status, ->(status) { where(status: status) }

  # Callbacks
  before_validation :set_defaults
  before_save :calculate_total_pages

  def total_pages
    return super if super.present?
    return 0 unless first_page && last_page
    last_page - first_page + 1
  end

  def total_words
    total_pages * effective_words_per_page
  end

  def remaining_pages
    total_pages - current_page
  end

  def remaining_words
    remaining_pages * effective_words_per_page
  end

  def progress_percentage
    return 0 if total_pages.zero?
    ((current_page.to_f / total_pages) * 100).round(1)
  end

  # Returns the actual book page number (accounting for first_page offset)
  # current_page = pages read, so actual position = first_page + pages_read
  def actual_current_page
    first_page + current_page
  end

  def effective_words_per_page
    words_per_page || user.default_words_per_page
  end

  def difficulty_modifier
    actual_difficulty_modifier || DIFFICULTY_MODIFIERS[difficulty.to_sym]
  end

  def actual_wpm
    sessions = reading_sessions.where.not(words_per_minute: nil)
    return nil if sessions.empty?
    sessions.average(:words_per_minute)&.to_f
  end

  def effective_reading_time_minutes
    wpm = actual_wpm || (user.effective_reading_speed * difficulty_modifier)
    return 0 if wpm.zero? || remaining_words.zero?
    (remaining_words / wpm).round
  end

  def estimated_reading_time_minutes
    return 0 if remaining_words.zero?

    effective_wpm = user.effective_reading_speed * difficulty_modifier
    (remaining_words / effective_wpm).round
  end

  def estimated_reading_time_hours
    (effective_reading_time_minutes / 60.0).round(1)
  end

  def formatted_estimated_time
    minutes = estimated_reading_time_minutes
    if minutes < 60
      "#{minutes} min"
    elsif minutes < 1440
      hours = (minutes / 60.0).round(1)
      "#{hours} hr"
    else
      days = (minutes / 1440.0).round(1)
      "#{days} days"
    end
  end

  def start_reading!
    update!(status: :reading) if unread?
  end

  def mark_completed!
    update!(status: :completed, current_page: total_pages)
  end

  def update_progress!(page_number)
    update!(current_page: [page_number, total_pages].min)
    mark_completed! if current_page >= total_pages
  end

  private

  def set_defaults
    self.current_page ||= 0
    self.difficulty ||= :average
    self.words_per_page ||= user&.default_words_per_page || 250
    self.first_page ||= 1
  end

  def calculate_total_pages
    self.total_pages = last_page - first_page + 1 if first_page && last_page
  end

  def last_page_after_first_page
    return unless first_page && last_page
    if last_page < first_page
      errors.add(:last_page, "must be greater than or equal to first page")
    end
  end
end
