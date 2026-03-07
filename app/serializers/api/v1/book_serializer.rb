module Api
  module V1
    class BookSerializer
      def initialize(book)
        @book = book
      end

      def as_json
        {
          id: @book.id,
          title: @book.title,
          author: @book.author,
          first_page: @book.first_page,
          last_page: @book.last_page,
          current_page: @book.current_page,
          total_pages: @book.total_pages,
          remaining_pages: @book.remaining_pages,
          progress_percentage: @book.progress_percentage,
          words_per_page: @book.words_per_page,
          difficulty: @book.difficulty,
          status: @book.status,
          cover_image_url: @book.cover_image_url,
          isbn: @book.isbn,
          estimated_reading_time_minutes: @book.effective_reading_time_minutes,
          actual_wpm: @book.actual_wpm,
          created_at: @book.created_at,
          updated_at: @book.updated_at
        }
      end

      def self.collection(books)
        books.map { |book| new(book).as_json }
      end
    end
  end
end
