class ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [:new, :create]
  before_action :set_reading_session, only: [:show, :edit, :update, :destroy, :complete]

  def index
    @reading_sessions = current_user.reading_sessions.recent.includes(:book)
    @reading_sessions = @reading_sessions.completed if params[:completed]
  end

  def show
  end

  def new
    @reading_session = @book.reading_sessions.build(
      user: current_user,
      started_at: Time.current,
      start_page: @book.current_page
    )
  end

  def create
    @reading_session = @book.reading_sessions.build(reading_session_params)
    @reading_session.user = current_user
    @reading_session.ended_at = Time.current

    # Calculate started_at from duration
    duration = params.dig(:reading_session, :duration_seconds).to_i
    @reading_session.started_at = Time.current - duration.seconds if duration > 0
    @reading_session.started_at ||= Time.current

    # Convert end_page from actual page number to relative pages
    if params.dig(:reading_session, :end_page).present?
      actual_end_page = params[:reading_session][:end_page].to_i
      @reading_session.end_page = actual_end_page - @book.first_page
    end

    if @reading_session.save
      @book.start_reading! if @book.unread?

      # Update book progress
      if @reading_session.end_page.present?
        @book.update_progress!(@reading_session.end_page)

        # Update daily quotas
        update_daily_quotas(@reading_session.pages_read)

        # Analyze difficulty
        DifficultyAnalyzer.new(@book).analyze!
      end

      redirect_to @reading_session, notice: "Great session! You read #{@reading_session.pages_read} pages in #{format_duration(@reading_session.duration_seconds)}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @reading_session.update(reading_session_params)
      redirect_to @reading_session, notice: "Reading session updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reading_session.destroy
    redirect_to reading_sessions_path, notice: "Reading session deleted."
  end

  def complete
    @reading_session.complete!(params[:end_page].to_i)

    # Update any active daily quotas
    update_daily_quotas(@reading_session.pages_read)

    # Analyze difficulty if we have enough sessions
    DifficultyAnalyzer.new(@reading_session.book).analyze!

    redirect_to @reading_session, notice: "Great reading session! You read #{@reading_session.pages_read} pages."
  end

  private

  def set_book
    @book = current_user.books.find(params[:book_id])
  end

  def set_reading_session
    @reading_session = current_user.reading_sessions.find(params[:id])
  end

  def reading_session_params
    params.require(:reading_session).permit(:start_page, :end_page, :started_at, :ended_at, :duration_seconds)
  end

  def format_duration(seconds)
    return "0 min" unless seconds&.positive?
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes} min"
    end
  end

  def update_daily_quotas(pages_read)
    current_user.reading_goals.active.where(book: @reading_session.book).each do |goal|
      quota = goal.today_quota
      quota&.record_pages!(pages_read)
    end
  end
end
