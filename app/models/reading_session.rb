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
  after_save :update_user_stats!
  after_destroy :update_user_stats!

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

  def formatted_duration
    return "0 min" unless duration_seconds&.positive?
    hours = duration_seconds / 3600
    minutes = (duration_seconds % 3600) / 60
    if hours > 0
      "#{hours}h #{minutes}m"
    elsif minutes > 0
      "#{minutes} min"
    else
      "#{duration_seconds} sec"
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
    self.words_per_minute = calculated_wpm
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
