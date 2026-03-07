module Api
  module V1
    class ReadingSessionSerializer
      def initialize(session)
        @session = session
      end

      def as_json
        {
          id: @session.id,
          book_id: @session.book_id,
          book_title: @session.book.title,
          started_at: @session.started_at,
          ended_at: @session.ended_at,
          start_page: @session.start_page,
          end_page: @session.end_page,
          duration_seconds: @session.effective_duration_seconds,
          pages_read: @session.pages_read,
          words_per_minute: @session.words_per_minute,
          in_progress: @session.in_progress?,
          untracked: @session.untracked?,
          formatted_duration: @session.formatted_duration,
          created_at: @session.created_at
        }
      end

      def self.collection(sessions)
        sessions.map { |session| new(session).as_json }
      end
    end
  end
end
