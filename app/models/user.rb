class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Associations
  has_many :books, dependent: :destroy
  has_many :reading_sessions, dependent: :destroy
  has_many :reading_goals, dependent: :destroy
  has_one :user_reading_stats, dependent: :destroy

  READING_PACE_TYPES = %w[books_per_year books_per_month books_per_week].freeze
  DEFAULT_AVG_BOOK_PAGES = 300

  # Enums
  enum :weekend_mode, { skip: 0, same: 1 }

  # Validations
  validates :default_words_per_page, numericality: { greater_than: 0 }
  validates :default_reading_speed_wpm, numericality: { greater_than: 0 }
  validates :max_concurrent_books, numericality: { greater_than: 0 }
  validates :weekday_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :weekend_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :reading_pace_type, inclusion: { in: READING_PACE_TYPES }, allow_nil: true
  validates :reading_pace_value, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :concurrency_limit, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  # Callbacks
  after_create :create_reading_stats

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  def effective_reading_speed
    user_reading_stats&.average_wpm || default_reading_speed_wpm
  end

  def includes_weekends?
    !skip?
  end

  def weekend_target
    skip? ? 0 : weekday_reading_minutes
  end

  def reading_pace_progress
    return nil unless reading_pace_type.present? && reading_pace_value.present?

    pace_config = {
      "books_per_year" => { days: 365, unit: "books/year", default_start: -> { Date.current.beginning_of_year } },
      "books_per_month" => { days: 30.44, unit: "books/month", default_start: -> { Date.current.beginning_of_month } },
      "books_per_week" => { days: 7, unit: "books/week", default_start: -> { Date.current.beginning_of_week(:monday) } }
    }

    config = pace_config[reading_pace_type]
    return nil unless config

    pace_start = reading_pace_set_on || config[:default_start].call
    days_elapsed = [(Date.current - pace_start).to_i, 1].max
    completed = books_completed_since(pace_start)
    actual_rate = completed.to_f / days_elapsed * config[:days]

    { current: completed, rate: actual_rate.round(1), target_rate: reading_pace_value,
      unit: config[:unit], period_label: "since #{pace_start.strftime('%b %-d')}" }
  end

  def derive_daily_minutes_from_pace
    return nil unless reading_pace_type.present? && reading_pace_value.present?

    case reading_pace_type
    when "books_per_year"
      calculate_daily_minutes_for_book_pace(365.0)
    when "books_per_month"
      calculate_daily_minutes_for_book_pace(30.44)
    when "books_per_week"
      calculate_daily_minutes_for_book_pace(7.0)
    end
  end

  def reading_pace_label
    return nil unless reading_pace_type.present?

    case reading_pace_type
    when "books_per_year" then "books/year"
    when "books_per_month" then "books/month"
    when "books_per_week" then "books/week"
    end
  end

  def effective_concurrency_limit
    concurrency_limit || max_concurrent_books
  end

  private

  def create_reading_stats
    build_user_reading_stats.save
  end

  def books_completed_since(start_date)
    books.where(status: :completed)
         .where("completed_at >= ?", start_date.beginning_of_day)
         .count
  end

  def calculate_daily_minutes_for_book_pace(days_in_period)
    avg_pages = books.average(:total_pages)&.to_f || DEFAULT_AVG_BOOK_PAGES
    avg_pages = DEFAULT_AVG_BOOK_PAGES if avg_pages <= 0
    words_per_book = avg_pages * (default_words_per_page || 250)
    minutes_per_book = words_per_book.to_f / effective_reading_speed
    books_per_day = reading_pace_value.to_f / days_in_period
    (minutes_per_book * books_per_day).ceil
  end
end
