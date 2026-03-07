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

        mode = %w[all title author isbn].include?(params[:mode]) ? params[:mode] : "all"
        service = GoogleBooksService.new
        results = service.search(query, limit: 8, mode: mode)

        # Mark books already in the user's collection
        user_isbns = current_user.books.where.not(isbn: [nil, ""]).pluck(:isbn).map(&:strip).to_set
        user_titles = current_user.books.pluck(:title).map { |t| t.strip.downcase }.to_set

        results.each do |book|
          book[:in_collection] = (book[:isbn].present? && user_isbns.include?(book[:isbn])) ||
                                 (book[:title].present? && user_titles.include?(book[:title].strip.downcase))
        end

        render json: { results: results }
      end
    end
  end
end
