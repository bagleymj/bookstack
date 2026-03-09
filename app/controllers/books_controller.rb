class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [:show, :edit, :update, :destroy, :start_reading, :mark_completed, :update_progress]

  def index
    @books = current_user.books.order(updated_at: :desc)
    @books = @books.by_status(params[:status]) if params[:status].present?
  end

  def show
    @reading_sessions = @book.reading_sessions.completed.recent.limit(10)
    @active_goal = @book.reading_goals.active.first
    @queued_goal = @book.reading_goals.queued.first unless @active_goal
  end

  def new
    @book = current_user.books.build
  end

  def create
    @book = current_user.books.build(book_params)

    if @book.save
      if params[:add_to_reading_list] == "1"
        add_to_reading_list!(@book)
        redirect_to pipeline_path, notice: "#{@book.title} added and scheduled."
      else
        redirect_to @book, notice: "Book was successfully added."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      reschedule_if_on_pipeline!
      redirect_to @book, notice: "Book was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @book.destroy
    redirect_to books_path, notice: "Book was successfully removed."
  end

  def start_reading
    @book.start_reading!
    redirect_to @book, notice: "Started reading #{@book.title}!"
  end

  def mark_completed
    @book.mark_completed!
    redirect_to @book, notice: "Congratulations on finishing #{@book.title}!"
  end

  def update_progress
    page = params[:page].to_i
    @book.update_progress!(page)
    redirect_to @book, notice: "Progress updated to page #{page}."
  end

  private

  def set_book
    @book = current_user.books.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :first_page, :last_page, :words_per_page, :difficulty, :cover_image_url, :isbn, :open_library_work_key)
  end

  def reschedule_if_on_pipeline!
    return unless @book.reading_goals.where(auto_scheduled: true).where.not(position: nil).exists?

    ReadingListScheduler.new(current_user).schedule!
  end

  def add_to_reading_list!(book)
    max_position = current_user.reading_goals.where.not(position: nil).maximum(:position) || 0
    current_user.reading_goals.create!(
      book: book,
      status: :queued,
      position: max_position + 1,
      auto_scheduled: true
    )
    ReadingListScheduler.new(current_user).schedule!
  end
end
