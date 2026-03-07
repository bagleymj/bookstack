require "rails_helper"

RSpec.describe "API V1 Reading Sessions", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }
  let(:book) { create(:book, :reading, user: user) }

  describe "GET /api/v1/reading_sessions" do
    it "returns user's reading sessions" do
      create(:reading_session, :completed, user: user, book: book)
      create(:reading_session, :completed) # another user's

      get "/api/v1/reading_sessions", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_sessions"].length).to eq(1)
    end
  end

  describe "GET /api/v1/reading_sessions/:id" do
    it "returns session details" do
      session = create(:reading_session, :completed, user: user, book: book)

      get "/api/v1/reading_sessions/#{session.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_session"]["id"]).to eq(session.id)
    end
  end

  describe "POST /api/v1/reading_sessions/start" do
    it "starts a new reading session" do
      post "/api/v1/reading_sessions/start", params: {
        book_id: book.id, start_page: book.current_page
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response["reading_session"]["in_progress"]).to be true
      expect(json_response["reading_session"]["book_id"]).to eq(book.id)
    end

    it "prevents starting two sessions simultaneously" do
      create(:reading_session, :in_progress, user: user, book: book)

      post "/api/v1/reading_sessions/start", params: {
        book_id: book.id
      }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/reading_sessions/:id/stop" do
    it "stops an in-progress session" do
      session = create(:reading_session, :in_progress, user: user, book: book)

      post "/api/v1/reading_sessions/#{session.id}/stop", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_session"]["ended_at"]).to be_present
    end

    it "returns error for already stopped session" do
      session = create(:reading_session, :completed, user: user, book: book)

      post "/api/v1/reading_sessions/#{session.id}/stop", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/reading_sessions/:id/complete" do
    it "completes a session with end page" do
      session = create(:reading_session, :in_progress, user: user, book: book, start_page: 50)

      post "/api/v1/reading_sessions/#{session.id}/complete", params: {
        end_page: 70
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      session.reload
      expect(session.end_page).to eq(70)
      expect(session.completed?).to be true
    end
  end

  describe "GET /api/v1/reading_sessions/active" do
    it "returns the active session" do
      session = create(:reading_session, :in_progress, user: user, book: book)

      get "/api/v1/reading_sessions/active", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_session"]["id"]).to eq(session.id)
    end

    it "returns null when no active session" do
      get "/api/v1/reading_sessions/active", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["reading_session"]).to be_nil
    end
  end

  describe "POST /api/v1/reading_sessions" do
    it "creates a manual (untracked) session" do
      post "/api/v1/reading_sessions", params: {
        book_id: book.id,
        start_page: 50,
        end_page: 70,
        duration_seconds: 1800,
        untracked: true
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response["reading_session"]["untracked"]).to be true
    end
  end

  describe "DELETE /api/v1/reading_sessions/:id" do
    it "deletes a session" do
      session = create(:reading_session, :completed, user: user, book: book)

      expect {
        delete "/api/v1/reading_sessions/#{session.id}", headers: headers
      }.to change(ReadingSession, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
