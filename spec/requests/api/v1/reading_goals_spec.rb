require "rails_helper"

RSpec.describe "API V1 Reading Goals", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }
  let(:book) { create(:book, :reading, user: user) }

  describe "GET /api/v1/reading_goals" do
    it "returns user's reading goals" do
      create(:reading_goal, user: user, book: book)

      get "/api/v1/reading_goals", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_goals"].length).to eq(1)
    end

    it "filters by status" do
      create(:reading_goal, user: user, book: book, status: :active)
      book2 = create(:book, user: user)
      create(:reading_goal, user: user, book: book2, status: :completed)

      get "/api/v1/reading_goals", params: { status: "active" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_goals"].length).to eq(1)
    end
  end

  describe "GET /api/v1/reading_goals/:id" do
    it "returns goal with quotas" do
      goal = create(:reading_goal, user: user, book: book)

      get "/api/v1/reading_goals/#{goal.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_goal"]["id"]).to eq(goal.id)
      expect(json_response["reading_goal"]).to have_key("daily_quotas")
    end
  end

  describe "POST /api/v1/reading_goals" do
    it "creates a new reading goal" do
      new_book = create(:book, user: user)

      post "/api/v1/reading_goals", params: {
        reading_goal: {
          book_id: new_book.id,
          started_on: Date.current.to_s,
          target_completion_date: 30.days.from_now.to_date.to_s
        }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response["reading_goal"]["book_id"]).to eq(new_book.id)
    end
  end

  describe "POST /api/v1/reading_goals/:id/mark_completed" do
    it "marks goal as completed" do
      goal = create(:reading_goal, user: user, book: book)

      post "/api/v1/reading_goals/#{goal.id}/mark_completed", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_goal"]["status"]).to eq("completed")
    end
  end

  describe "POST /api/v1/reading_goals/:id/mark_abandoned" do
    it "marks goal as abandoned" do
      goal = create(:reading_goal, user: user, book: book)

      post "/api/v1/reading_goals/#{goal.id}/mark_abandoned", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_goal"]["status"]).to eq("abandoned")
    end
  end

  describe "DELETE /api/v1/reading_goals/:id" do
    it "deletes a goal" do
      goal = create(:reading_goal, user: user, book: book)

      expect {
        delete "/api/v1/reading_goals/#{goal.id}", headers: headers
      }.to change(ReadingGoal, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
