require "rails_helper"

RSpec.describe "ReadingSessions", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }
  let(:book) { create(:book, :reading, user: user, current_page: 50, last_page: 300) }

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

    context "with an in-progress session" do
      let(:reading_session) { create(:reading_session, :in_progress, user: user, book: book) }

      it "shows the pause button" do
        get reading_session_path(reading_session)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pause")
      end
    end

    context "with a completed session" do
      let(:reading_session) { create(:reading_session, :completed, user: user, book: book) }

      it "shows the edit link" do
        get reading_session_path(reading_session)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Edit Session")
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

    it "updates book progress" do
      post complete_reading_session_path(reading_session), params: { end_page: 75 }
      expect(book.reload.current_page).to eq(75)
    end

    it "updates daily quotas for active goals" do
      goal = create(:reading_goal, user: user, book: book, status: :active)
      quota = goal.today_quota

      post complete_reading_session_path(reading_session), params: { end_page: 75 }

      expect(quota.reload.actual_pages).to eq(25)
    end
  end

  describe "GET /reading_sessions/:id/edit" do
    context "with a completed session" do
      let(:reading_session) { create(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 75) }

      it "renders the edit form" do
        get edit_reading_session_path(reading_session)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Edit Reading Session")
        expect(response.body).to include("Save Changes")
      end
    end

    context "with an in-progress session" do
      let(:reading_session) { create(:reading_session, :in_progress, user: user, book: book) }

      it "redirects back to the session" do
        get edit_reading_session_path(reading_session)

        expect(response).to redirect_to(reading_session)
      end
    end
  end

  describe "PATCH /reading_sessions/:id" do
    let(:reading_session) do
      create(:reading_session, :completed, user: user, book: book,
             start_page: 50, end_page: 75, duration_seconds: 1800)
    end

    it "updates the end page" do
      patch reading_session_path(reading_session), params: {
        reading_session: { end_page: 80 }
      }

      expect(response).to redirect_to(reading_session)
      expect(reading_session.reload.end_page).to eq(80)
    end

    it "updates book progress when end_page changes" do
      patch reading_session_path(reading_session), params: {
        reading_session: { end_page: 100 }
      }

      expect(book.reload.current_page).to eq(100)
    end

    it "rejects invalid end_page" do
      patch reading_session_path(reading_session), params: {
        reading_session: { end_page: 30 }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /books/:book_id/reading_sessions/start" do
    it "creates an in-progress session" do
      expect {
        post start_book_reading_sessions_path(book)
      }.to change(ReadingSession, :count).by(1)

      session = ReadingSession.last
      expect(session.in_progress?).to be true
      expect(session.start_page).to eq(book.current_page)
    end

    it "redirects if user already has an active session" do
      create(:reading_session, :in_progress, user: user, book: book)
      other_book = create(:book, :reading, user: user)

      post start_book_reading_sessions_path(other_book)

      expect(response).to redirect_to(ReadingSession.in_progress.first)
    end

    it "transitions unread book to reading" do
      unread_book = create(:book, :unread, user: user)
      post start_book_reading_sessions_path(unread_book)

      expect(unread_book.reload.status).to eq("reading")
    end
  end

  describe "DELETE /reading_sessions/:id" do
    let!(:reading_session) { create(:reading_session, :completed, user: user, book: book) }

    it "deletes the session" do
      expect {
        delete reading_session_path(reading_session)
      }.to change(ReadingSession, :count).by(-1)
    end

    it "redirects to sessions index" do
      delete reading_session_path(reading_session)
      expect(response).to redirect_to(reading_sessions_path)
    end
  end

  describe "POST /books/:book_id/reading_sessions (untracked)" do
    it "creates an untracked session" do
      post book_reading_sessions_path(book), params: {
        reading_session: {
          start_page: 50,
          end_page: 70,
          duration_seconds: 1200,
          untracked: true
        }
      }

      session = ReadingSession.last
      expect(session.untracked?).to be true
      expect(session.pages_read).to eq(20)
    end
  end
end
