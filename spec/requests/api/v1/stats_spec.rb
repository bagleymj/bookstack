require "rails_helper"

RSpec.describe "API V1 Stats", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "GET /api/v1/stats" do
    it "returns user reading stats" do
      get "/api/v1/stats", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response).to have_key("stats")
      expect(json_response["stats"]).to have_key("total_sessions")
      expect(json_response["stats"]).to have_key("average_wpm")
    end
  end
end
