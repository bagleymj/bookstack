module Api
  module V1
    module Auth
      class RegistrationsController < ActionController::API
        def create
          user = User.new(sign_up_params)

          if user.save
            token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
            response.set_header("Authorization", "Bearer #{token}")

            render json: {
              user: {
                id: user.id,
                email: user.email,
                name: user.name
              },
              token: token,
              message: "Signed up successfully."
            }, status: :created
          else
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def sign_up_params
          params.require(:user).permit(:email, :password, :password_confirmation, :name)
        end
      end
    end
  end
end
