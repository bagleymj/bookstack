module Api
  module V1
    class ReadingGoalSerializer
      def initialize(goal)
        @goal = goal
      end

      def as_json
        {
          id: @goal.id,
          book_id: @goal.book_id,
          book_title: @goal.book.title,
          started_on: @goal.started_on,
          target_completion_date: @goal.target_completion_date,
          include_weekends: @goal.include_weekends?,
          status: @goal.status,
          progress_percentage: @goal.progress_percentage,
          pages_per_day: @goal.pages_per_day,
          minutes_per_day: @goal.calculated_minutes_per_day,
          days_remaining: @goal.reading_days_remaining,
          on_track: @goal.on_track?,
          tracking_status: @goal.tracking_status,
          position: @goal.position,
          auto_scheduled: @goal.auto_scheduled?,
          has_unresolved_discrepancy: @goal.has_unresolved_discrepancy?,
          created_at: @goal.created_at,
          updated_at: @goal.updated_at
        }
      end

      def as_json_with_quotas
        as_json.merge(
          today_quota: serialize_quota(@goal.today_quota),
          daily_quotas: @goal.daily_quotas.order(:date).map { |q| serialize_quota(q) }
        )
      end

      def self.collection(goals)
        goals.map { |goal| new(goal).as_json }
      end

      private

      def serialize_quota(quota)
        return nil unless quota
        DailyQuotaSerializer.new(quota).as_json
      end
    end
  end
end
