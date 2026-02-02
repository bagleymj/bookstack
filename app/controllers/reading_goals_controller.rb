class ReadingGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reading_goal, only: [:show, :edit, :update, :destroy, :mark_completed, :mark_abandoned, :redistribute, :catch_up]

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
    if @reading_goal.update(reading_goal_params)
      @reading_goal.redistribute_quotas!
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
    @reading_goal.redistribute_quotas!
    redirect_to @reading_goal, notice: "Quotas have been redistributed based on current progress."
  end

  def catch_up
    @reading_goal.catch_up!
    redirect_to @reading_goal, notice: "Caught up! Missed quotas have been marked as completed."
  end

  private

  def set_reading_goal
    @reading_goal = current_user.reading_goals.find(params[:id])
  end

  def reading_goal_params
    params.require(:reading_goal).permit(:book_id, :target_completion_date, :started_on, :include_weekends)
  end
end
