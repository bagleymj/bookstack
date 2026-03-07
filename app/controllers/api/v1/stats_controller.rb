module Api
  module V1
    class StatsController < BaseController
      def show
        stats = current_user.user_reading_stats
        unless stats
          return render json: { stats: nil }
        end

        wpp = current_user.default_words_per_page
        pages_per_hour = stats.total_sessions > 0 ? ((stats.average_wpm * 60.0) / wpp).round(1) : 0
        avg_pages_per_session = stats.total_sessions > 0 ? (stats.total_pages_read.to_f / stats.total_sessions).round(1) : 0

        render json: {
          stats: {
            total_sessions: stats.total_sessions,
            total_pages_read: stats.total_pages_read,
            total_reading_time_seconds: stats.total_reading_time_seconds,
            total_reading_time_formatted: stats.total_reading_time_formatted,
            average_wpm: stats.average_wpm,
            pages_per_hour: pages_per_hour,
            avg_pages_per_session: avg_pages_per_session,
            last_calculated_at: stats.last_calculated_at
          }
        }
      end
    end
  end
end
