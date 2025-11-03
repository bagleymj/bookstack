class UserBooksController < ApplicationController
  def index
    @user_books = Current.user.user_books
  end

  def show
    @user_book = UserBook.find(params[:id])
  end

  def create
    book = Book.find(params[:book_id])
    user = Current.user
    user.books << book

    redirect_back fallback_location: books_path
  end

  def destroy
    user_book = Current.user.user_books.find_by(book_id: params[:book_id]) 
    user_book.destroy

    redirect_back fallback_location: books_path
  end
end
