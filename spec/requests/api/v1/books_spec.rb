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
  end
end
