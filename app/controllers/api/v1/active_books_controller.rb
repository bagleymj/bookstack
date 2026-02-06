module Api
  module V1
    class ActiveBooksController < ApplicationController
      before_action :authenticate_user!

      def index
        books = current_user.books.in_progress.order(updated_at: :desc)

        render json: books.map { |book|
          {
            id: book.id,
            title: book.title,
            author: book.author,
            current_page: book.actual_current_page,
            total_pages: book.total_pages,
            progress: book.progress_percentage
          }
        }
      end
    end
  end
end
