require "rails_helper"

RSpec.describe "API V1 Profile", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "GET /api/v1/profile" do
    it "returns user profile" do
      get "/api/v1/profile", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["email"]).to eq(user.email)
      expect(json_response["profile"]).to have_key("stats")
    end

    it "includes pace and concurrency fields" do
      user.update!(reading_pace_type: "books_per_year", reading_pace_value: 50, concurrency_limit: 3)
      get "/api/v1/profile", headers: headers

      profile = json_response["profile"]
      expect(profile["reading_pace_type"]).to eq("books_per_year")
      expect(profile["reading_pace_value"]).to eq(50)
      expect(profile["reading_pace_label"]).to eq("books/year")
      expect(profile["concurrency_limit"]).to eq(3)
      expect(profile["derived_daily_minutes"]).to be_a(Integer)
    end

    it "returns nil concurrency_limit when not set" do
      get "/api/v1/profile", headers: headers

      expect(json_response["profile"]["concurrency_limit"]).to be_nil
    end
  end

  describe "PATCH /api/v1/profile" do
    it "updates user settings" do
      patch "/api/v1/profile", params: {
        profile: { name: "Updated Name" }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["name"]).to eq("Updated Name")
    end

    it "updates concurrency_limit" do
      patch "/api/v1/profile", params: {
        profile: { concurrency_limit: 5 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["concurrency_limit"]).to eq(5)
    end

    it "updates pace fields" do
      patch "/api/v1/profile", params: {
        profile: { reading_pace_type: "books_per_month", reading_pace_value: 4 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["profile"]["reading_pace_type"]).to eq("books_per_month")
      expect(json_response["profile"]["reading_pace_value"]).to eq(4)
    end

    it "rejects minutes_per_day pace type" do
      patch "/api/v1/profile", params: {
        profile: { reading_pace_type: "minutes_per_day", reading_pace_value: 30 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns errors for invalid update" do
      patch "/api/v1/profile", params: {
        profile: { default_reading_speed_wpm: -1 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/profile/reset_pace" do
    before do
      user.update!(
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: 100.days.ago.to_date
      )
    end

    it "resets reading_pace_set_on to today" do
      post "/api/v1/profile/reset_pace", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.reading_pace_set_on).to eq(Date.current)
    end

    it "preserves pace type and value" do
      post "/api/v1/profile/reset_pace", headers: headers, as: :json

      user.reload
      expect(user.reading_pace_type).to eq("books_per_year")
      expect(user.reading_pace_value).to eq(50)
    end

    it "destroys queued auto-scheduled reading goals" do
      book = create(:book, user: user, status: :unread)
      create(:reading_goal, user: user, book: book, status: :queued, auto_scheduled: true, position: 1)

      expect {
        post "/api/v1/profile/reset_pace", headers: headers, as: :json
      }.to change { user.reading_goals.where(status: :queued, auto_scheduled: true).count }.by(-1)
    end

    it "returns updated profile" do
      post "/api/v1/profile/reset_pace", headers: headers, as: :json

      expect(json_response["profile"]["reading_pace_type"]).to eq("books_per_year")
      expect(json_response["profile"]["reading_pace_value"]).to eq(50)
    end
  end
end
