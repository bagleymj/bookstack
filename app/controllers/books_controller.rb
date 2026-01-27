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
  end

  def new
    @book = current_user.books.build
  end

  def create
    @book = current_user.books.build(book_params)

    if @book.save
      redirect_to @book, notice: "Book was successfully added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
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
    actual_page = params[:page].to_i
    # Convert actual book page to pages read (relative to first_page)
    pages_read = actual_page - @book.first_page
    @book.update_progress!(pages_read)
    redirect_to @book, notice: "Progress updated to page #{actual_page}."
  end

  private

  def set_book
    @book = current_user.books.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :first_page, :last_page, :words_per_page, :difficulty, :cover_image_url, :isbn)
  end
end
