class PipelineBooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_pipeline, only: [:create, :reorder]
  before_action :set_pipeline_book, only: [:update, :destroy]

  def create
    book = current_user.books.find(params[:book_id])
    @pipeline_book = @pipeline.add_book(
      book,
      track: params[:track]&.to_i || 1,
      planned_start_date: params[:planned_start_date],
      planned_end_date: params[:planned_end_date]
    )

    respond_to do |format|
      format.html { redirect_to @pipeline, notice: "#{book.title} added to pipeline." }
      format.turbo_stream
    end
  end

  def update
    if @pipeline_book.update(pipeline_book_params)
      respond_to do |format|
        format.html { redirect_to @pipeline_book.pipeline, notice: "Book schedule updated." }
        format.turbo_stream
        format.json { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to @pipeline_book.pipeline, alert: "Could not update book." }
        format.json { render json: @pipeline_book.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    pipeline = @pipeline_book.pipeline
    book_title = @pipeline_book.book.title
    @pipeline_book.destroy

    respond_to do |format|
      format.html { redirect_to pipeline, notice: "#{book_title} removed from pipeline." }
      format.turbo_stream
    end
  end

  def reorder
    params[:positions].each do |position_data|
      pb = @pipeline.pipeline_books.find(position_data[:id])
      pb.update!(
        position: position_data[:position],
        track: position_data[:track]
      )
    end

    head :ok
  end

  private

  def set_pipeline
    @pipeline = current_user.pipelines.find(params[:pipeline_id])
  end

  def set_pipeline_book
    @pipeline_book = PipelineBook.joins(:pipeline)
                                  .where(pipelines: { user_id: current_user.id })
                                  .find(params[:id])
  end

  def pipeline_book_params
    params.require(:pipeline_book).permit(:position, :track, :planned_start_date, :planned_end_date)
  end
end
