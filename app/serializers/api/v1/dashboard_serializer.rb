module Api
  module V1
    class DashboardSerializer
      def initialize(user)
        @user = user
      end

      def as_json
        {
          today: today_data,
          stats: aggregate_stats,
          discrepancies: discrepancy_data
        }
      end

      private

      def today_data
        today_sessions = @user.reading_sessions.completed.for_date(Date.current)
        today_quotas = DailyQuota.joins(:reading_goal)
                                 .where(reading_goals: { user_id: @user.id, status: :active })
                                 .where(date: Date.current)
                                 .where.not(status: :missed)
                                 .includes(reading_goal: :book)

        {
          quotas: today_quotas.map { |q| DailyQuotaSerializer.new(q).as_json.merge(
            book_title: q.book.title,
            book_id: q.book.id,
            goal_id: q.reading_goal_id
          )},
          pages_read: today_sessions.sum(:pages_read),
          reading_time_seconds: today_sessions.sum(&:effective_duration_seconds).to_i,
          total_minutes_remaining: today_quotas.sum(&:estimated_minutes_remaining),
          active_session: active_session_data
        }
      end

      def active_session_data
        session = @user.reading_sessions.in_progress.includes(:book).first
        return nil unless session

        ReadingSessionSerializer.new(session).as_json
      end

      def aggregate_stats
        stats = @user.user_reading_stats

        week_sessions = @user.reading_sessions.completed
                          .where(started_at: Date.current.beginning_of_week(:monday).beginning_of_day..Date.current.end_of_day)

        yearly_goals = @user.reading_goals.where(target_completion_date: Date.current.all_year)

        {
          reading_streak: calculate_reading_streak,
          books_in_progress: @user.books.in_progress.count,
          books_completed_all_time: @user.books.finished.count,
          yearly_books_scheduled: yearly_goals.select(:book_id).distinct.count,
          yearly_books_completed: yearly_goals.where(status: :completed).select(:book_id).distinct.count,
          pages_this_week: week_sessions.sum(:pages_read),
          time_this_week_seconds: week_sessions.sum(&:effective_duration_seconds).to_i,
          average_wpm: stats&.average_wpm,
          total_sessions: stats&.total_sessions || 0,
          total_pages_read: stats&.total_pages_read || 0,
          total_reading_time_formatted: stats&.total_reading_time_formatted || "0 min"
        }
      end

      def discrepancy_data
        @user.reading_goals.active
             .includes(:book, :daily_quotas)
             .select(&:has_unresolved_discrepancy?)
             .map do |goal|
          disc = goal.yesterday_discrepancy
          {
            goal_id: goal.id,
            book_id: goal.book_id,
            book_title: goal.book.title,
            type: disc[:type],
            pages: disc[:pages]
          }
        end
      end

      def calculate_reading_streak
        dates = @user.reading_sessions
                  .completed
                  .where(untracked: false)
                  .pluck(:started_at)
                  .map(&:to_date)
                  .uniq
                  .sort
                  .reverse

        return 0 if dates.empty?

        streak = 0
        expected_date = Date.current
        expected_date = Date.yesterday if dates.first != Date.current

        dates.each do |date|
          if date == expected_date
            streak += 1
            expected_date -= 1.day
          elsif date < expected_date
            break
          end
        end

        streak
      end
    end
  end
end
