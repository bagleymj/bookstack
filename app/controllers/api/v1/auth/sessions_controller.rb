module Api
  module V1
    module Auth
      class SessionsController < ActionController::API
        def create
          user = User.find_by(email: sign_in_params[:email])

          if user&.valid_password?(sign_in_params[:password])
            token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
            response.set_header("Authorization", "Bearer #{token}")

            render json: {
              user: {
                id: user.id,
                email: user.email,
                name: user.name
              },
              token: token,
              message: "Logged in successfully."
            }, status: :ok
          else
            render json: { error: "Invalid email or password." }, status: :unauthorized
          end
        end

        def destroy
          token = request.headers["Authorization"]&.split(" ")&.last

          if token
            begin
              payload = Warden::JWTAuth::TokenDecoder.new.call(token)
              JwtDenylist.create!(jti: payload["jti"], exp: Time.at(payload["exp"]))
              render json: { message: "Logged out successfully." }, status: :ok
            rescue JWT::DecodeError
              render json: { error: "Invalid token." }, status: :unauthorized
            end
          else
            render json: { error: "No token provided." }, status: :unauthorized
          end
        end

        private

        def sign_in_params
          params.require(:user).permit(:email, :password)
        end
      end
    end
  end
end
