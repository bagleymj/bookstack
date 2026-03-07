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

      def authenticate_user!
        return if current_user

        render json: { error: "You need to sign in or sign up before continuing." }, status: :unauthorized
      end

      def current_user
        @current_user ||= warden&.authenticate(scope: :user)
      end

      def warden
        request.env["warden"]
      end
    end
  end
end
