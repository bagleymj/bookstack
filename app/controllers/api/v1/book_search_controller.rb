module Api
  module V1
    class BookSearchController < ApplicationController
      before_action :authenticate_user!

      def index
        query = params[:q].to_s.strip

        if query.blank?
          render json: { results: [] }
          return
        end

        service = GoogleBooksService.new
        results = service.search_works(query, limit: 8, search_type: params[:search_type])

        render json: { results: results }
      end

      def editions
        work_key = params[:work_key].to_s.strip

        if work_key.blank?
          render json: { editions: [] }
          return
        end

        service = GoogleBooksService.new
        editions = service.fetch_editions(work_key)

        # Overlay local edition cache data (recommended page ranges)
        editions = EditionCacheService.new.overlay_local_data(editions)

        # Mark editions already in the user's collection
        user_isbns = current_user.books.where.not(isbn: [nil, ""]).pluck(:isbn).map(&:strip).to_set

        editions.each do |edition|
          edition[:in_collection] = edition[:isbn].present? && user_isbns.include?(edition[:isbn])
        end

        render json: { editions: editions }
      end
    end
  end
end
