class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # Associations
  has_many :books, dependent: :destroy
  has_many :reading_sessions, dependent: :destroy
  has_many :reading_goals, dependent: :destroy
  has_one :user_reading_stats, dependent: :destroy

  READING_GOAL_TYPES = %w[books_per_year books_per_month books_per_week minutes_per_day].freeze

  # Validations
  validates :default_words_per_page, numericality: { greater_than: 0 }
  validates :default_reading_speed_wpm, numericality: { greater_than: 0 }
  validates :max_concurrent_books, numericality: { greater_than: 0 }
  validates :weekday_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :weekend_reading_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :reading_goal_type, inclusion: { in: READING_GOAL_TYPES }, allow_nil: true
  validates :reading_goal_value, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  # Callbacks
  after_create :create_reading_stats

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  def effective_reading_speed
    user_reading_stats&.average_wpm || default_reading_speed_wpm
  end

  def includes_weekends?
    weekend_reading_minutes > 0
  end

  def reading_goal_progress
    return nil unless reading_goal_type.present? && reading_goal_value.present?

    case reading_goal_type
    when "books_per_year"
      completed = books_completed_in_period(Date.current.beginning_of_year, Date.current.end_of_year)
      expected = expected_books_by_now(:year)
      { current: completed, target: reading_goal_value, expected: expected, period: "this year" }
    when "books_per_month"
      completed = books_completed_in_period(Date.current.beginning_of_month, Date.current.end_of_month)
      expected = expected_books_by_now(:month)
      { current: completed, target: reading_goal_value, expected: expected, period: "this month" }
    when "books_per_week"
      week_start = Date.current.beginning_of_week(:monday)
      completed = books_completed_in_period(week_start, week_start + 6.days)
      expected = expected_books_by_now(:week)
      { current: completed, target: reading_goal_value, expected: expected, period: "this week" }
    when "minutes_per_day"
      today_seconds = reading_sessions.completed.for_date(Date.current).sum(&:effective_duration_seconds).to_i
      today_minutes = today_seconds / 60
      { current: today_minutes, target: reading_goal_value, expected: reading_goal_value, period: "today" }
    end
  end

  def reading_goal_label
    return nil unless reading_goal_type.present?

    case reading_goal_type
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

  def books_completed_in_period(start_date, end_date)
    reading_goals.where(status: :completed)
                 .where(target_completion_date: start_date..end_date)
                 .select(:book_id).distinct.count
  end

  def expected_books_by_now(period)
    case period
    when :year
      day_of_year = Date.current.yday
      days_in_year = Date.current.end_of_year.yday
      (reading_goal_value.to_f * day_of_year / days_in_year).round(1)
    when :month
      day_of_month = Date.current.day
      days_in_month = Date.current.end_of_month.day
      (reading_goal_value.to_f * day_of_month / days_in_month).round(1)
    when :week
      day_of_week = (Date.current.cwday) # 1=Monday, 7=Sunday
      (reading_goal_value.to_f * day_of_week / 7).round(1)
    end
  end
end
