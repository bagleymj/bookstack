class ReadingGoalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reading_goal, only: [:show, :destroy, :mark_completed, :mark_abandoned]

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
      respond_to do |format|
        format.html { redirect_to @reading_goal, notice: "Reading goal created! Daily quotas have been generated." }
        format.json { render json: { id: @reading_goal.id, message: "Reading goal created!" }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          @books = current_user.books.where.not(status: :completed)
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: @reading_goal.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    was_auto_scheduled = @reading_goal.auto_scheduled?
    @reading_goal.destroy
    ReadingListScheduler.new(current_user).schedule! if was_auto_scheduled
    respond_to do |format|
      format.html { redirect_to pipeline_path, notice: "Reading goal deleted." }
      format.json { head :no_content }
    end
  end

  def mark_completed
    @reading_goal.mark_completed!
    redirect_to pipeline_path, notice: "Congratulations on completing your reading goal!"
  end

  def mark_abandoned
    @reading_goal.mark_abandoned!
    respond_to do |format|
      format.html { redirect_to pipeline_path, notice: "Reading goal marked as abandoned." }
      format.json { head :no_content }
    end
  end

  private

  def set_reading_goal
    @reading_goal = current_user.reading_goals.find(params[:id])
  end

  def reading_goal_params
    params.require(:reading_goal).permit(:book_id, :target_completion_date, :started_on)
  end
end
