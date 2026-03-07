module Api
  module V1
    class BooksController < BaseController
      before_action :set_book, only: [ :show, :update, :destroy, :start_reading, :mark_completed, :update_progress ]

      def index
        books = current_user.books.order(updated_at: :desc)
        books = books.by_status(params[:status]) if params[:status].present?
        render json: { books: BookSerializer.collection(books) }
      end

      def show
        render json: {
          book: BookSerializer.new(@book).as_json,
          active_goal: serialize_active_goal,
          recent_sessions: ReadingSessionSerializer.collection(
            @book.reading_sessions.completed.recent.limit(10)
          )
        }
      end

      def create
        book = current_user.books.build(book_params)
        if book.save
          render json: { book: BookSerializer.new(book).as_json }, status: :created
        else
          render_errors book.errors.full_messages
        end
      end

      def update
        if @book.update(book_params)
          render json: { book: BookSerializer.new(@book).as_json }
        else
          render_errors @book.errors.full_messages
        end
      end

      def destroy
        @book.destroy
        head :no_content
      end

      def start_reading
        @book.start_reading!
        render json: { book: BookSerializer.new(@book.reload).as_json }
      end

      def mark_completed
        @book.mark_completed!
        render json: { book: BookSerializer.new(@book.reload).as_json }
      end

      def update_progress
        page = params[:current_page].to_i
        @book.update_progress!(page)
        render json: { book: BookSerializer.new(@book.reload).as_json }
      end

      private

      def set_book
        @book = current_user.books.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def book_params
        params.require(:book).permit(
          :title, :author, :first_page, :last_page,
          :words_per_page, :difficulty, :cover_image_url, :isbn
        )
      end

      def serialize_active_goal
        goal = @book.reading_goals.where(status: [ :active, :queued ]).first
        return nil unless goal
        ReadingGoalSerializer.new(goal).as_json
      end
    end
  end
end
