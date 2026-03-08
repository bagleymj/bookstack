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

  READING_PACE_TYPES = %w[books_per_year books_per_month books_per_week minutes_per_day].freeze
  DEFAULT_AVG_BOOK_PAGES = 300

  # Enums
  enum :weekend_mode, { skip: 0, same: 1, capped: 2 }

  # Validations
  validates :default_words_per_page, numericality: { greater_than: 0 }
  validates :default_reading_speed_wpm, numericality: { greater_than: 0 }
  validates :max_concurrent_books, numericality: { greater_than: 0 }
  validates :weekday_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :weekend_reading_minutes, numericality: { greater_than: 0 }, if: :capped?
  validates :weekend_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :reading_pace_type, inclusion: { in: READING_PACE_TYPES }, allow_nil: true
  validates :reading_pace_value, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

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

  def weekend_budget
    case weekend_mode
    when "skip"   then 0
    when "same"   then weekday_reading_minutes
    when "capped" then weekend_reading_minutes
    end
  end

  def reading_pace_progress
    return nil unless reading_pace_type.present? && reading_pace_value.present?

    case reading_pace_type
    when "books_per_year"
      pace_start = reading_pace_set_on || Date.current.beginning_of_year
      days_elapsed = [(Date.current - pace_start).to_i, 1].max
      completed = books_completed_since(pace_start)
      actual_rate = completed.to_f / days_elapsed * 365
      { current: completed, rate: actual_rate.round(1), target_rate: reading_pace_value,
        unit: "books/year", period_label: "since #{pace_start.strftime('%b %-d')}" }
    when "books_per_month"
      pace_start = reading_pace_set_on || Date.current.beginning_of_month
      days_elapsed = [(Date.current - pace_start).to_i, 1].max
      completed = books_completed_since(pace_start)
      actual_rate = completed.to_f / days_elapsed * 30.44
      { current: completed, rate: actual_rate.round(1), target_rate: reading_pace_value,
        unit: "books/month", period_label: "since #{pace_start.strftime('%b %-d')}" }
    when "books_per_week"
      pace_start = reading_pace_set_on || Date.current.beginning_of_week(:monday)
      days_elapsed = [(Date.current - pace_start).to_i, 1].max
      completed = books_completed_since(pace_start)
      actual_rate = completed.to_f / days_elapsed * 7
      { current: completed, rate: actual_rate.round(1), target_rate: reading_pace_value,
        unit: "books/week", period_label: "since #{pace_start.strftime('%b %-d')}" }
    when "minutes_per_day"
      pace_start = reading_pace_set_on || Date.current
      days_elapsed = [(Date.current - pace_start).to_i, 1].max
      total_seconds = reading_sessions.completed
                        .where("started_at >= ?", pace_start.beginning_of_day)
                        .sum(&:effective_duration_seconds).to_i
      avg_minutes_per_day = total_seconds / 60.0 / days_elapsed
      today_seconds = reading_sessions.completed.for_date(Date.current).sum(&:effective_duration_seconds).to_i
      today_minutes = today_seconds / 60
      { current: today_minutes, rate: avg_minutes_per_day.round, target_rate: reading_pace_value,
        unit: "min/day", period_label: "avg since #{pace_start.strftime('%b %-d')}" }
    end
  end

  def derive_daily_minutes_from_pace
    return nil unless reading_pace_type.present? && reading_pace_value.present?

    case reading_pace_type
    when "minutes_per_day"
      reading_pace_value
    when "books_per_year"
      calculate_daily_minutes_for_book_pace(365.0)
    when "books_per_month"
      calculate_daily_minutes_for_book_pace(30.44)
    when "books_per_week"
      calculate_daily_minutes_for_book_pace(7.0)
    end
  end

  def apply_pace_to_schedule!
    calendar_daily = derive_daily_minutes_from_pace
    return unless calendar_daily

    weekly_total = calendar_daily * 7.0
    case weekend_mode
    when "skip"
      update!(weekday_reading_minutes: (weekly_total / 5).ceil)
    when "same"
      update!(weekday_reading_minutes: calendar_daily, weekend_reading_minutes: calendar_daily)
    when "capped"
      weekday_mins = [(weekly_total - weekend_reading_minutes * 2) / 5.0, 1].max.ceil
      update!(weekday_reading_minutes: weekday_mins)
    end
  end

  def reading_pace_label
    return nil unless reading_pace_type.present?

    case reading_pace_type
    when "books_per_year" then "books/year"
    when "books_per_month" then "books/month"
    when "books_per_week" then "books/week"
    when "minutes_per_day" then "min/day"
    end
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
