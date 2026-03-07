require "rails_helper"

RSpec.describe "API V1 Daily Quotas", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "PATCH /api/v1/daily_quotas/:id" do
    it "records pages for a quota" do
      book = create(:book, :reading, user: user)
      goal = create(:reading_goal, user: user, book: book)
      quota = goal.daily_quotas.find_by(date: Date.current) ||
              create(:daily_quota, reading_goal: goal, date: Date.current, target_pages: 10)

      patch "/api/v1/daily_quotas/#{quota.id}", params: {
        actual_pages: 5
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["daily_quota"]["actual_pages"]).to be >= 5
    end

    it "returns 404 for another user's quota" do
      other_book = create(:book)
      other_goal = create(:reading_goal, user: other_book.user, book: other_book)
      quota = other_goal.daily_quotas.first

      patch "/api/v1/daily_quotas/#{quota.id}", params: {
        actual_pages: 5
      }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
