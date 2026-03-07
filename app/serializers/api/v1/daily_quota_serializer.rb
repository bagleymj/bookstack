module Api
  module V1
    class DailyQuotaSerializer
      def initialize(quota)
        @quota = quota
      end

      def as_json
        {
          id: @quota.id,
          reading_goal_id: @quota.reading_goal_id,
          date: @quota.date,
          target_pages: @quota.target_pages,
          actual_pages: @quota.actual_pages,
          status: @quota.status,
          pages_remaining: @quota.pages_remaining,
          percentage_complete: @quota.percentage_complete,
          effectively_complete: @quota.effectively_complete?,
          estimated_minutes_remaining: @quota.estimated_minutes_remaining
        }
      end

      def self.collection(quotas)
        quotas.map { |quota| new(quota).as_json }
      end
    end
  end
end
