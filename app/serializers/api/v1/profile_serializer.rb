module Api
  module V1
    class ProfileSerializer
      def initialize(user)
        @user = user
      end

      def as_json
        {
          id: @user.id,
          email: @user.email,
          name: @user.name,
          default_words_per_page: @user.default_words_per_page,
          default_reading_speed_wpm: @user.default_reading_speed_wpm,
          effective_reading_speed: @user.effective_reading_speed,
          max_concurrent_books: @user.max_concurrent_books,
          weekday_reading_minutes: @user.weekday_reading_minutes,
          weekend_reading_minutes: @user.weekend_reading_minutes,
          includes_weekends: @user.includes_weekends?,
          stats: stats_json
        }
      end

      private

      def stats_json
        stats = @user.user_reading_stats
        return nil unless stats

        {
          total_sessions: stats.total_sessions,
          total_pages_read: stats.total_pages_read,
          total_reading_time_seconds: stats.total_reading_time_seconds,
          total_reading_time_formatted: stats.total_reading_time_formatted,
          average_wpm: stats.average_wpm,
          last_calculated_at: stats.last_calculated_at
        }
      end
    end
  end
end
