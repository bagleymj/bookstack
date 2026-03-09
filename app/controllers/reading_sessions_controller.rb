class ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [:new, :create, :start]
  before_action :set_reading_session, only: [:show, :edit, :update, :destroy, :complete]

  def index
    @reading_sessions = current_user.reading_sessions.recent.includes(:book)
    @reading_sessions = @reading_sessions.completed if params[:completed]
  end

  def show
  end

  def start
    existing = current_user.reading_sessions.in_progress.includes(:book).first
    if existing
      redirect_to existing, alert: "You already have an active reading session for \"#{existing.book.title}\"."
      return
    end

    @reading_session = @book.reading_sessions.create!(
      user: current_user,
      started_at: Time.current,
      start_page: @book.current_page
    )

    @book.start_reading! if @book.unread?

    redirect_to @reading_session, notice: "Reading session started! Your timer is running."
  end

  def new
    @reading_session = @book.reading_sessions.build(
      user: current_user,
      started_at: Time.current,
      start_page: @book.current_page
    )

    # Find today's quota for this book (if there's an active reading goal)
    active_goal = current_user.reading_goals.active.find_by(book: @book)
    @today_quota = active_goal&.today_quota
  end

  def create
    @reading_session = @book.reading_sessions.build(reading_session_params)
    @reading_session.user = current_user
    @reading_session.ended_at = Time.current

    # Calculate started_at from duration
    duration = params.dig(:reading_session, :duration_seconds).to_i
    @reading_session.started_at = Time.current - duration.seconds if duration > 0
    @reading_session.started_at ||= Time.current

    # end_page is stored as the actual page number - no conversion needed

    if @reading_session.save
      @book.start_reading! if @book.unread?

      # Update book progress
      if @reading_session.end_page.present?
        @book.update_progress!(@reading_session.end_page)

        # Update daily quotas
        update_daily_quotas(@reading_session.pages_read)

        # Analyze difficulty
        DifficultyAnalyzer.new(@book).analyze!

        # Reschedule if this session is against a queued book on the reading list
        reschedule_if_queued!(@book)
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
    params.require(:reading_session).permit(:start_page, :end_page, :started_at, :ended_at, :duration_seconds, :untracked)
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

  def reschedule_if_queued!(book)
    if book.reading_goals.where(status: :queued, auto_scheduled: true).exists?
      ReadingListScheduler.new(current_user).schedule!
    end
  end
end
