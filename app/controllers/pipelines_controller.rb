class PipelinesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_pipeline, only: [:show, :edit, :update, :destroy, :auto_schedule]

  def index
    @pipelines = current_user.pipelines.includes(pipeline_books: :book)
  end

  def show
    @pipeline_books = @pipeline.pipeline_books.includes(:book).ordered
    @available_books = current_user.books.where.not(id: @pipeline.books.pluck(:id))
  end

  def new
    @pipeline = current_user.pipelines.build
  end

  def create
    @pipeline = current_user.pipelines.build(pipeline_params)

    if @pipeline.save
      redirect_to @pipeline, notice: "Pipeline created!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @pipeline.update(pipeline_params)
      redirect_to @pipeline, notice: "Pipeline updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @pipeline.destroy
    redirect_to pipelines_path, notice: "Pipeline deleted."
  end

  def auto_schedule
    @pipeline.auto_schedule!
    redirect_to @pipeline, notice: "Pipeline has been automatically scheduled based on your reading speed."
  end

  private

  def set_pipeline
    @pipeline = current_user.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description)
  end
end
