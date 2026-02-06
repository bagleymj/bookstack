class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book

  # Validations
  validates :started_at, presence: true
  validates :start_page, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :end_page, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :end_page_greater_than_start_page, if: :end_page

  # Scopes
  scope :completed, -> { where.not(ended_at: nil) }
  scope :in_progress, -> { where(ended_at: nil) }
  scope :recent, -> { order(started_at: :desc) }
  scope :for_date, ->(date) { where(started_at: date.beginning_of_day..date.end_of_day) }

  # Callbacks
  before_save :calculate_metrics, if: :completed?
  after_save :update_user_stats!, unless: :untracked?
  after_destroy :update_user_stats!, unless: :untracked?

  def completed?
    ended_at.present? && end_page.present?
  end

  def in_progress?
    ended_at.nil?
  end

  def complete!(end_page_number)
    update!(
      ended_at: Time.current,
      end_page: end_page_number
    )
    update_book_progress!
  end

  def duration
    return nil unless ended_at
    ended_at - started_at
  end

  def calculated_pages_read
    return 0 unless end_page && start_page
    [end_page - start_page, 0].max
  end

  # Returns actual book page numbers (accounting for first_page offset)
  def actual_start_page
    book.first_page + start_page
  end

  def actual_end_page
    return nil unless end_page
    book.first_page + end_page
  end

  # Returns the duration to use for display/calculations
  # For tracked sessions: actual duration from timer
  # For untracked sessions: estimated duration based on WPM snapshot
  def effective_duration_seconds
    untracked? ? (estimated_duration_seconds || duration_seconds) : duration_seconds
  end

  def effective_duration_minutes
    return 0 unless effective_duration_seconds&.positive?
    (effective_duration_seconds / 60.0).round
  end

  def formatted_duration
    seconds = effective_duration_seconds
    return "0 min" unless seconds&.positive?
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    if hours > 0
      "#{hours}h #{minutes}m"
    elsif minutes > 0
      "#{minutes} min"
    else
      "#{seconds} sec"
    end
  end

  def calculated_wpm
    return nil unless completed? && duration_seconds&.positive?

    words_read = calculated_pages_read * book.effective_words_per_page
    minutes = duration_seconds / 60.0
    return nil if minutes.zero?

    (words_read / minutes).round(1)
  end

  private

  def calculate_metrics
    # Only calculate duration if not already set
    if duration_seconds.blank? && ended_at && started_at
      self.duration_seconds = (ended_at - started_at).to_i
    end
    self.pages_read = calculated_pages_read
    self.words_per_minute = untracked? ? nil : calculated_wpm

    # For untracked sessions, calculate estimated duration based on WPM snapshot
    if untracked?
      calculate_estimated_duration
    end
  end

  def calculate_estimated_duration
    # Snapshot WPM: prefer book's actual WPM, fallback to user average * difficulty
    self.wpm_snapshot = book.actual_wpm || (user.effective_reading_speed * book.difficulty_modifier)

    return if wpm_snapshot.nil? || wpm_snapshot.zero? || pages_read.nil? || pages_read.zero?

    words_read = pages_read * book.effective_words_per_page
    minutes = words_read / wpm_snapshot
    self.estimated_duration_seconds = (minutes * 60).round
  end

  def update_book_progress!
    book.update_progress!(end_page) if end_page
  end

  def update_user_stats!
    ReadingStatsCalculator.new(user).recalculate!
  end

  def end_page_greater_than_start_page
    if end_page && start_page && end_page < start_page
      errors.add(:end_page, "must be greater than or equal to start page")
    end
  end
end
