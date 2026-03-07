require "rails_helper"

RSpec.describe "API V1 Auth", type: :request do
  describe "POST /api/v1/auth/sign_in" do
    let!(:user) { create(:user, email: "test@example.com", password: "password123") }

    it "returns JWT token in Authorization header" do
      post "/api/v1/auth/sign_in", params: {
        user: { email: "test@example.com", password: "password123" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to be_present
      expect(json_response["user"]["email"]).to eq("test@example.com")
    end

    it "returns 401 for invalid credentials" do
      post "/api/v1/auth/sign_in", params: {
        user: { email: "test@example.com", password: "wrong" }
      }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/auth/sign_up" do
    it "creates a new user and returns JWT" do
      post "/api/v1/auth/sign_up", params: {
        user: {
          email: "new@example.com",
          password: "password123",
          password_confirmation: "password123",
          name: "New User"
        }
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Authorization"]).to be_present
      expect(json_response["user"]["email"]).to eq("new@example.com")
      expect(json_response["user"]["name"]).to eq("New User")
    end

    it "returns errors for invalid registration" do
      post "/api/v1/auth/sign_up", params: {
        user: { email: "", password: "short" }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response["errors"]).to be_present
    end
  end

  describe "DELETE /api/v1/auth/sign_out" do
    let!(:user) { create(:user) }

    it "revokes the JWT token" do
      headers = jwt_headers(user)

      delete "/api/v1/auth/sign_out", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["message"]).to include("Logged out")
    end
  end
end
