require "rails_helper"

RSpec.describe "ReadingSessions", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }
  let(:book) { create(:book, :reading, user: user) }

  before { sign_in user }

  describe "GET /reading_sessions/:id" do
    context "with an in-progress session and active goal with today's quota" do
      let(:reading_session) { create(:reading_session, :in_progress, user: user, book: book) }
      let!(:goal) { create(:reading_goal, user: user, book: book, status: :active) }

      it "shows the today's target page" do
        get reading_session_path(reading_session)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Today's Target")
      end
    end

    context "with an in-progress session and no active goal" do
      let(:reading_session) { create(:reading_session, :in_progress, user: user, book: book) }

      it "shows book progress instead of target page" do
        get reading_session_path(reading_session)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Book Progress")
        expect(response.body).not_to include("Today's Target")
      end
    end
  end

  describe "POST /reading_sessions/:id/complete" do
    let(:reading_session) { create(:reading_session, :in_progress, user: user, book: book, start_page: 50) }

    it "rejects end_page less than start_page" do
      post complete_reading_session_path(reading_session), params: { end_page: 30 }

      expect(response).to redirect_to(reading_session)
      follow_redirect!
      expect(response.body).to include("End page must be greater than or equal to start page")
    end

    it "completes the session when end_page is valid" do
      post complete_reading_session_path(reading_session), params: { end_page: 75 }

      expect(response).to redirect_to(reading_session)
      reading_session.reload
      expect(reading_session.end_page).to eq(75)
      expect(reading_session.ended_at).to be_present
    end
  end
end
