module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_user!

      private

      def render_error(message, status: :unprocessable_entity)
        render json: { error: message }, status: status
      end

      def render_errors(errors, status: :unprocessable_entity)
        render json: { errors: errors }, status: status
      end

      def render_not_found
        render json: { error: "Not found" }, status: :not_found
      end
    end
  end
end
