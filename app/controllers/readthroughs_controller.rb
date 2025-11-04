class ReadthroughsController < ApplicationController
  def new
    @readthrough = Readthrough.new(user_book_id: params[:user_book_id])
  end

  def create
    @readthrough = Readthrough.new(readthrough_params)
    if @readthrough.save
      redirect_to @readthrough.user_book
    else 
      render :new, status: :unprocessable_entity 
    end
  end


  private

  def readthrough_params
    params.expect(readthrough: [ :start_date, :end_date, :user_book_id ])
  end
end
