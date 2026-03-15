require "rails_helper"

RSpec.describe "API V1 Books", type: :request do
  let(:user) { create(:user) }
  let(:headers) { jwt_headers(user) }

  describe "GET /api/v1/books" do
    it "returns all user books" do
      create_list(:book, 3, user: user)
      create(:book) # another user's book

      get "/api/v1/books", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["books"].length).to eq(3)
    end

    it "filters by status" do
      create(:book, :reading, user: user)
      create(:book, :unread, user: user)

      get "/api/v1/books", params: { status: "reading" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["books"].length).to eq(1)
      expect(json_response["books"][0]["status"]).to eq("reading")
    end

    it "returns 401 without auth" do
      get "/api/v1/books"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/books/:id" do
    it "returns book details" do
      book = create(:book, :reading, user: user)

      get "/api/v1/books/#{book.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["book"]["id"]).to eq(book.id)
      expect(json_response["book"]["title"]).to eq(book.title)
    end

    it "returns 404 for another user's book" do
      other_book = create(:book)

      get "/api/v1/books/#{other_book.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/books" do
    it "creates a new book" do
      post "/api/v1/books", params: {
        book: { title: "New Book", author: "Author", first_page: 1, last_page: 200 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response["book"]["title"]).to eq("New Book")
      expect(json_response["book"]["total_pages"]).to eq(200)
    end

    it "records edition page range when isbn is present" do
      post "/api/v1/books", params: {
        book: { title: "Meditations", author: "Marcus Aurelius", first_page: 1, last_page: 256,
                isbn: "9780140449334" }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      edition = Edition.find_by(isbn: "9780140449334")
      expect(edition).to be_present
      expect(edition.recommended_first_page).to eq(1)
      expect(edition.recommended_last_page).to eq(256)
    end

    it "returns errors for invalid book" do
      post "/api/v1/books", params: {
        book: { title: "" }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response["errors"]).to be_present
    end
  end

  describe "PATCH /api/v1/books/:id" do
    it "updates a book" do
      book = create(:book, user: user)

      patch "/api/v1/books/#{book.id}", params: {
        book: { title: "Updated Title" }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["book"]["title"]).to eq("Updated Title")
    end

    it "rebuilds quotas when page range changes on a locked goal" do
      paced_user = create(:user,
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: Date.current.beginning_of_year,
        default_reading_speed_wpm: 250,
        max_concurrent_books: 3,
        weekend_mode: :same,
        weekday_reading_minutes: 60,
        weekend_reading_minutes: 60)

      book = create(:book, :reading, user: paced_user, first_page: 1, last_page: 400, current_page: 50)
      goal = create(:reading_goal,
        user: paced_user, book: book, status: :active,
        started_on: Date.current,
        target_completion_date: 28.days.from_now.to_date,
        auto_scheduled: true, position: 1)
      ProfileAwareQuotaCalculator.new(goal, paced_user).generate_quotas!

      # Lock the goal by creating a reading session earlier this week (not today)
      create(:reading_session, :completed, user: paced_user, book: book,
        started_at: 2.days.ago, ended_at: 2.days.ago + 1.hour,
        start_page: 1, end_page: 20)

      original_total = goal.daily_quotas.where("date >= ?", Date.current).sum(:target_pages)

      patch "/api/v1/books/#{book.id}", params: {
        book: { last_page: 300 }
      }, headers: jwt_headers(paced_user), as: :json

      expect(response).to have_http_status(:ok)

      goal.reload
      new_total = goal.daily_quotas.where("date >= ?", Date.current).sum(:target_pages)

      expect(book.reload.total_pages).to eq(300)
      expect(new_total).to be < original_total
      expect(new_total).to eq(book.remaining_pages)
    end

    it "updates edition fields together" do
      book = create(:book, user: user, isbn: "old-isbn", last_page: 200)

      patch "/api/v1/books/#{book.id}", params: {
        book: {
          isbn: "9780140449334",
          cover_image_url: "https://books.google.com/thumb.jpg",
          last_page: 256
        }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      book.reload
      expect(book.isbn).to eq("9780140449334")
      expect(book.last_page).to eq(256)

      edition = Edition.find_by(isbn: "9780140449334")
      expect(edition).to be_present
    end
  end

  describe "DELETE /api/v1/books/:id" do
    it "deletes a book" do
      book = create(:book, user: user)

      expect {
        delete "/api/v1/books/#{book.id}", headers: headers
      }.to change(Book, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/books/:id/start_reading" do
    it "transitions book to reading status" do
      book = create(:book, :unread, user: user)

      post "/api/v1/books/#{book.id}/start_reading", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["book"]["status"]).to eq("reading")
    end
  end

  describe "POST /api/v1/books/:id/mark_completed" do
    it "marks book as completed" do
      book = create(:book, :reading, user: user)

      post "/api/v1/books/#{book.id}/mark_completed", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["book"]["status"]).to eq("completed")
    end
  end

  describe "POST /api/v1/books/:id/update_progress" do
    it "updates current page" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)

      post "/api/v1/books/#{book.id}/update_progress", params: { current_page: 100 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response["book"]["current_page"]).to eq(100)
    end

    it "creates an untracked session when advancing forward" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)

      expect {
        post "/api/v1/books/#{book.id}/update_progress", params: { current_page: 100 }, headers: headers, as: :json
      }.to change(ReadingSession, :count).by(1)

      session = ReadingSession.last
      expect(session.start_page).to eq(50)
      expect(session.end_page).to eq(100)
      expect(session.untracked?).to be true
    end

    it "does not create a session when page is not advancing" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)

      expect {
        post "/api/v1/books/#{book.id}/update_progress", params: { current_page: 50 }, headers: headers, as: :json
      }.not_to change(ReadingSession, :count)
    end

    it "updates daily quota actual_pages" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)
      goal = create(:reading_goal, user: user, book: book, status: :active)
      quota = goal.today_quota

      post "/api/v1/books/#{book.id}/update_progress", params: { current_page: 80 }, headers: headers, as: :json

      expect(quota.reload.actual_pages).to eq(30)
    end

    it "transitions unread book to reading" do
      book = create(:book, :unread, user: user, current_page: 1, last_page: 300)

      post "/api/v1/books/#{book.id}/update_progress", params: { current_page: 20 }, headers: headers, as: :json

      expect(book.reload.status).to eq("reading")
    end
  end
end
