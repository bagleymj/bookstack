module Api
  module V1
    class ReadingSessionsController < BaseController
      before_action :set_session, only: [ :show, :update, :destroy, :stop, :complete ]

      def index
        sessions = current_user.reading_sessions.recent.includes(:book)
        sessions = sessions.limit(params[:limit] || 20)
        render json: { reading_sessions: ReadingSessionSerializer.collection(sessions) }
      end

      def show
        render json: { reading_session: ReadingSessionSerializer.new(@session).as_json }
      end

      def create
        book = current_user.books.find(params[:book_id])
        session = current_user.reading_sessions.build(
          book: book,
          started_at: Time.current,
          start_page: params[:start_page] || book.current_page,
          end_page: params[:end_page],
          ended_at: params[:end_page] ? Time.current : nil,
          untracked: params[:untracked] || false
        )

        if params[:duration_seconds].present?
          session.duration_seconds = params[:duration_seconds].to_i
          session.started_at = Time.current - session.duration_seconds.seconds
          session.ended_at = Time.current
        end

        if session.save
          book.start_reading! if book.unread?
          update_daily_quotas(session) if session.completed?
          reschedule_if_queued!(book)
          render json: { reading_session: ReadingSessionSerializer.new(session).as_json }, status: :created
        else
          render_errors session.errors.full_messages
        end
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def update
        if @session.update(session_update_params)
          render json: { reading_session: ReadingSessionSerializer.new(@session).as_json }
        else
          render_errors @session.errors.full_messages
        end
      end

      def destroy
        @session.destroy
        head :no_content
      end

      # POST /api/v1/reading_sessions/start
      def start
        book = current_user.books.find(params[:book_id])
        session = current_user.reading_sessions.build(
          book: book,
          started_at: Time.current,
          start_page: params[:start_page] || book.current_page
        )

        if session.save
          book.start_reading! if book.unread?
          render json: { reading_session: ReadingSessionSerializer.new(session).as_json }, status: :created
        else
          render_errors session.errors.full_messages
        end
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      # POST /api/v1/reading_sessions/:id/stop
      def stop
        unless @session.in_progress?
          return render_error("Session is not in progress")
        end

        @session.update!(ended_at: Time.current)
        render json: { reading_session: ReadingSessionSerializer.new(@session.reload).as_json }
      end

      # POST /api/v1/reading_sessions/:id/complete
      def complete
        unless @session.in_progress? || (@session.ended_at.present? && @session.end_page.nil?)
          return render_error("Session cannot be completed")
        end

        end_page = params[:end_page].to_i
        @session.complete!(end_page)
        update_daily_quotas(@session)

        if @session.book.reading_sessions.completed.count >= 3
          DensityAnalyzer.new(@session.book).analyze!
        end

        render json: { reading_session: ReadingSessionSerializer.new(@session.reload).as_json }
      end

      # GET /api/v1/reading_sessions/active
      def active
        session = current_user.reading_sessions.in_progress.includes(:book).first
        if session
          render json: { reading_session: ReadingSessionSerializer.new(session).as_json }
        else
          render json: { reading_session: nil }
        end
      end

      private

      def set_session
        @session = current_user.reading_sessions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def session_update_params
        params.permit(:start_page, :end_page, :started_at, :ended_at)
      end

      def update_daily_quotas(session)
        return unless session.completed?

        active_goals = session.book.reading_goals.active.includes(:daily_quotas)
        active_goals.each do |goal|
          quota = goal.today_quota
          next unless quota
          quota.record_pages!(session.calculated_pages_read)
        end
      end

      def reschedule_if_queued!(book)
        if book.reading_goals.where(status: :queued, auto_scheduled: true).exists?
          ReadingListScheduler.new(current_user).schedule!
        end
      end
    end
  end
end
