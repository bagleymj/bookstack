require "rails_helper"

RSpec.describe "API V1 Profile", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "GET /api/v1/profile" do
    it "returns user profile" do
      get "/api/v1/profile", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["email"]).to eq(user.email)
      expect(json_response["profile"]["default_words_per_page"]).to eq(user.default_words_per_page)
      expect(json_response["profile"]).to have_key("stats")
    end
  end

  describe "PATCH /api/v1/profile" do
    it "updates user settings" do
      patch "/api/v1/profile", params: {
        profile: { name: "Updated Name", default_words_per_page: 300 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["name"]).to eq("Updated Name")
      expect(json_response["profile"]["default_words_per_page"]).to eq(300)
    end

    it "returns errors for invalid update" do
      patch "/api/v1/profile", params: {
        profile: { default_words_per_page: -1 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
