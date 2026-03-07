require "rails_helper"

RSpec.describe "API V1 Dashboard", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "GET /api/v1/dashboard" do
    it "returns dashboard data" do
      get "/api/v1/dashboard", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response).to have_key("today")
      expect(json_response).to have_key("stats")
      expect(json_response).to have_key("discrepancies")
      expect(json_response["today"]).to have_key("quotas")
      expect(json_response["today"]).to have_key("active_session")
      expect(json_response["stats"]).to have_key("reading_streak")
    end

    it "includes active session when present" do
      book = create(:book, :reading, user: user)
      create(:reading_session, :in_progress, user: user, book: book)

      get "/api/v1/dashboard", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["today"]["active_session"]).to be_present
    end

    it "returns 401 without auth" do
      get "/api/v1/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
