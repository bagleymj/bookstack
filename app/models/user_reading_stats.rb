class UserReadingStats < ApplicationRecord
  self.table_name = "user_reading_stats"

  belongs_to :user

  def recalculate!
    sessions = user.reading_sessions.completed.where(untracked: false)

    update!(
      total_sessions: sessions.count,
      total_pages_read: sessions.sum(:pages_read),
      total_reading_time_seconds: sessions.sum(:duration_seconds),
      average_wpm: calculate_average_wpm(sessions),
      last_calculated_at: Time.current
    )
  end

  def total_reading_time_formatted
    return "0 min" if total_reading_time_seconds.zero?

    hours = total_reading_time_seconds / 3600
    minutes = (total_reading_time_seconds % 3600) / 60

    if hours.zero?
      "#{minutes} min"
    else
      "#{hours}h #{minutes}m"
    end
  end

  private

  def calculate_average_wpm(sessions)
    valid_sessions = sessions.where.not(words_per_minute: nil)
    return user.default_reading_speed_wpm if valid_sessions.empty?

    # Weighted average by duration
    total_weighted = valid_sessions.sum { |s| s.words_per_minute * s.duration_seconds }
    total_duration = valid_sessions.sum(:duration_seconds)

    return user.default_reading_speed_wpm if total_duration.zero?

    (total_weighted / total_duration).round(1)
  end
end
