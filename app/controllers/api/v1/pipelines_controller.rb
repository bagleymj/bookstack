module Api
  module V1
    class PipelinesController < ApplicationController
      before_action :authenticate_user!
      before_action :set_pipeline

      def timeline_data
        render json: {
          pipeline: {
            id: @pipeline.id,
            name: @pipeline.name,
            start_date: @pipeline.timeline_start_date,
            end_date: @pipeline.timeline_end_date
          },
          books: @pipeline.pipeline_books.includes(:book).map(&:as_timeline_data)
        }
      end

      private

      def set_pipeline
        @pipeline = current_user.pipelines.find(params[:id])
      end
    end
  end
end
