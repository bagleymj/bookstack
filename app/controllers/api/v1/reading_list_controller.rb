module Api
  module V1
    class ReadingListController < ApplicationController
      before_action :authenticate_user!

      # POST /api/v1/reading_list — add a book to the reading list
      def create
        book = current_user.books.find(params[:book_id])

        # Determine next position
        max_position = current_user.reading_goals
                                    .where.not(position: nil)
                                    .maximum(:position) || 0

        goal = current_user.reading_goals.build(
          book: book,
          status: :queued,
          position: max_position + 1,
          auto_scheduled: true
        )

        if goal.save
          ReadingListScheduler.new(current_user).schedule!

          goals = current_user.reading_goals.in_reading_list.includes(:book)
          render json: { goals: goals.map(&:as_pipeline_data) }, status: :created
        else
          render json: { errors: goal.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/reading_list/reorder — update positions
      def reorder
        positions = params[:positions] || []

        ActiveRecord::Base.transaction do
          positions.each do |pos|
            goal = current_user.reading_goals.find(pos[:id])
            goal.update!(position: pos[:position])
          end
        end

        ReadingListScheduler.new(current_user).schedule!

        goals = current_user.reading_goals.in_reading_list.includes(:book)
        render json: { goals: goals.map(&:as_pipeline_data) }
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      # GET /api/v1/reading_list/impact_preview — compute schedule impact for a hypothetical book
      def impact_preview
        first_page = (params[:first_page] || 1).to_i
        last_page = (params[:last_page] || 0).to_i
        density = params[:density] || "average"

        if last_page <= first_page
          render json: { delta: 0 }
          return
        end

        # Build a transient book to compute impact (not persisted)
        book = current_user.books.build(
          first_page: first_page,
          last_page: last_page,
          total_pages: last_page - first_page + 1,
          density: density,
          title: "preview"
        )

        delta = ScheduleImpactCalculator.new(current_user).impact_for(book)
        render json: { delta: delta }
      end

      # DELETE /api/v1/reading_list/:id — remove from list
      def destroy
        goal = current_user.reading_goals.find(params[:id])

        if goal.queued? || (goal.auto_scheduled? && !goal.has_reading_sessions?)
          goal.destroy
        else
          goal.update!(position: nil, auto_scheduled: false)
        end

        # Recompact positions
        recompact_positions!

        ReadingListScheduler.new(current_user).schedule!

        goals = current_user.reading_goals.in_reading_list.includes(:book)
        render json: { goals: goals.map(&:as_pipeline_data) }
      end

      private

      def recompact_positions!
        current_user.reading_goals
                    .where.not(position: nil)
                    .order(:position)
                    .each_with_index do |goal, index|
          goal.update_column(:position, index + 1)
        end
      end
    end
  end
end
