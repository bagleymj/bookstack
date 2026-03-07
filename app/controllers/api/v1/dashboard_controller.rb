module Api
  module V1
    class DashboardController < BaseController
      def show
        render json: DashboardSerializer.new(current_user).as_json
      end
    end
  end
end
