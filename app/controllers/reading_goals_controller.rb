class ReadingGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reading_goal, only: [:show, :edit, :update, :destroy, :mark_completed, :mark_abandoned, :redistribute, :catch_up, :resolve_discrepancy]

  def show
    @daily_quotas = @reading_goal.daily_quotas.order(:date)
    @today_quota = @reading_goal.today_quota
  end

  def new
    @reading_goal = current_user.reading_goals.build
    @reading_goal.started_on = Date.current
    @books = current_user.books.where.not(status: :completed)
  end

  def create
    @reading_goal = current_user.reading_goals.build(reading_goal_params)

    if @reading_goal.save
      redirect_to @reading_goal, notice: "Reading goal created! Daily quotas have been generated."
    else
      @books = current_user.books.where.not(status: :completed)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @books = current_user.books.where.not(status: :completed)
  end

  def update
    old_started_on = @reading_goal.started_on
    old_target_date = @reading_goal.target_completion_date

    if @reading_goal.update(reading_goal_params)
      dates_changed = @reading_goal.started_on != old_started_on ||
                      @reading_goal.target_completion_date != old_target_date

      if dates_changed
        # Regenerate quotas when dates change
        @reading_goal.daily_quotas.destroy_all
        @reading_goal.daily_quotas.reload  # Clear association cache
        QuotaCalculator.new(@reading_goal).generate_quotas!
      else
        @reading_goal.redistribute_quotas!
      end
      redirect_to @reading_goal, notice: "Reading goal updated and quotas recalculated."
    else
      @books = current_user.books.where.not(status: :completed)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reading_goal.destroy
    redirect_to pipeline_path, notice: "Reading goal deleted."
  end

  def mark_completed
    @reading_goal.mark_completed!
    redirect_to pipeline_path, notice: "Congratulations on completing your reading goal!"
  end

  def mark_abandoned
    @reading_goal.mark_abandoned!
    redirect_to pipeline_path, notice: "Reading goal marked as abandoned."
  end

  def redistribute
    if request.get?
      # Show the redistribute form with defaults
      @current_page = @reading_goal.book.current_page
      @actual_current_page = @reading_goal.book.actual_current_page
      @start_date = Date.current
      @min_date = Date.current
      @max_date = @reading_goal.target_completion_date
      render :redistribute
    else
      # Perform the redistribution with provided params
      actual_page = params[:current_page].to_i
      start_date = Date.parse(params[:start_date]) rescue Date.current

      # Convert actual page number to relative pages read
      pages_read = actual_page - @reading_goal.book.first_page

      # Update book progress if different
      if pages_read != @reading_goal.book.current_page
        @reading_goal.book.update!(current_page: pages_read)
      end

      # Redistribute from the specified date
      @reading_goal.redistribute_quotas!(from_date: start_date)
      redirect_to @reading_goal, notice: "Quotas have been redistributed from #{start_date.strftime('%B %d')}."
    end
  end

  def catch_up
    @reading_goal.catch_up!
    redirect_to @reading_goal, notice: "Caught up! Missed quotas have been marked as completed."
  end

  def resolve_discrepancy
    strategy = params[:strategy]&.to_sym

    unless [:redistribute, :apply_to_today].include?(strategy)
      redirect_to root_path, alert: "Invalid discrepancy resolution strategy."
      return
    end

    discrepancy = @reading_goal.yesterday_discrepancy

    unless discrepancy
      redirect_to root_path, notice: "No discrepancy to resolve."
      return
    end

    @reading_goal.resolve_discrepancy!(strategy)

    message = case strategy
    when :redistribute
      if discrepancy[:type] == :behind
        "Missed pages spread across remaining days."
      else
        "Extra reading spread across remaining days - future quotas reduced!"
      end
    when :apply_to_today
      if discrepancy[:type] == :behind
        "#{discrepancy[:pages]} pages added to today's goal. Time to catch up!"
      else
        "#{discrepancy[:pages]} bonus pages credited to today!"
      end
    end

    redirect_to root_path, notice: message
  end

  private

  def set_reading_goal
    @reading_goal = current_user.reading_goals.find(params[:id])
  end

  def reading_goal_params
    params.require(:reading_goal).permit(:book_id, :target_completion_date, :started_on, :include_weekends)
  end
end
