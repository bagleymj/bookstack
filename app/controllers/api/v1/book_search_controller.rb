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
        results = service.search(query, limit: 8)

        render json: { results: results }
      end
    end
  end
end
