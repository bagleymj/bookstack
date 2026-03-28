require "rails_helper"

RSpec.describe "Goodreads", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }

  before { sign_in user }

  describe "GET /goodreads" do
    it "renders the import/export page" do
      get goodreads_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /goodreads/preview" do
    let(:csv_content) do
      <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Meditations,Marcus Aurelius,"Aurelius, Marcus",,="0140449337",="9780140449334",0,4.25,Penguin Classics,Paperback,256,2006,180,,2024/01/15,,,to-read,,,,0,,,,,,,,
        2,The Republic,Plato,"Plato, ",,,,0,4.0,,,420,380BC,,,,,read,,,,1,,,,,,,,
      CSV
    end

    it "parses the uploaded CSV and shows preview" do
      file = Rack::Test::UploadedFile.new(StringIO.new(csv_content), "text/csv", false, original_filename: "goodreads.csv")
      post preview_goodreads_path, params: { file: file }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meditations")
      expect(response.body).to include("The Republic")
    end

    it "redirects with alert when no file is provided" do
      post preview_goodreads_path
      expect(response).to redirect_to(goodreads_path)
      follow_redirect!
      expect(response.body).to include("Please select a CSV file")
    end

    it "filters entries by selected shelves" do
      file = Rack::Test::UploadedFile.new(StringIO.new(csv_content), "text/csv", false, original_filename: "goodreads.csv")
      post preview_goodreads_path, params: { file: file, shelves: ["to-read"] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meditations")
      expect(response.body).not_to include("The Republic")
    end

    it "shows all shelves when none are selected" do
      file = Rack::Test::UploadedFile.new(StringIO.new(csv_content), "text/csv", false, original_filename: "goodreads.csv")
      post preview_goodreads_path, params: { file: file, shelves: [] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meditations")
      expect(response.body).to include("The Republic")
    end

    it "redirects when selected shelves match no books" do
      csv_with_only_read = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Meditations,Marcus Aurelius,"Aurelius, Marcus",,="0140449337",="9780140449334",0,4.25,Penguin Classics,Paperback,256,2006,180,,2024/01/15,,,read,,,,1,,,,,,,,
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv_with_only_read), "text/csv", false, original_filename: "goodreads.csv")
      post preview_goodreads_path, params: { file: file, shelves: ["to-read"] }

      expect(response).to redirect_to(goodreads_path)
      follow_redirect!
      expect(response.body).to include("No books found")
    end

    it "marks existing books by ISBN" do
      create(:book, user: user, isbn: "9780140449334", title: "Meditations", last_page: 256)

      file = Rack::Test::UploadedFile.new(StringIO.new(csv_content), "text/csv", false, original_filename: "goodreads.csv")
      post preview_goodreads_path, params: { file: file }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Already in library")
    end
  end

  describe "POST /goodreads/import" do
    it "creates books from selected entries" do
      expect {
        post import_goodreads_path, params: {
          books: [
            { title: "Meditations", author: "Marcus Aurelius", isbn: "9780140449334", last_page: "256", status: "unread" },
            { title: "The Republic", author: "Plato", isbn: "", last_page: "420", status: "completed" }
          ]
        }
      }.to change(Book, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meditations")
      expect(response.body).to include("The Republic")
    end

    it "skips duplicates by ISBN" do
      create(:book, user: user, isbn: "9780140449334", title: "Meditations", last_page: 256)

      expect {
        post import_goodreads_path, params: {
          books: [
            { title: "Meditations", author: "Marcus Aurelius", isbn: "9780140449334", last_page: "256", status: "unread" }
          ]
        }
      }.not_to change(Book, :count)
    end

    it "redirects when no books are selected" do
      post import_goodreads_path, params: { books: [] }
      expect(response).to redirect_to(goodreads_path)
    end
  end

  describe "GET /goodreads/export" do
    before do
      create(:book, :unread, user: user, title: "Unread Book", last_page: 200, isbn: "9781234567890")
      create(:book, :completed, user: user, title: "Read Book", last_page: 300)
    end

    it "downloads a CSV file" do
      get export_goodreads_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("bookstack_export_")
    end

    it "includes all books in the export" do
      get export_goodreads_path
      csv = CSV.parse(response.body, headers: true)
      expect(csv.size).to eq(2)
    end

    it "filters by status when specified" do
      get export_goodreads_path(status: :unread)
      csv = CSV.parse(response.body, headers: true)
      expect(csv.size).to eq(1)
      expect(csv.first["Title"]).to eq("Unread Book")
    end

    it "produces a valid Goodreads-format CSV" do
      get export_goodreads_path
      csv = CSV.parse(response.body, headers: true)
      expect(csv.headers.size).to eq(31)
      expect(csv.headers).to include("Exclusive Shelf", "ISBN13")
    end
  end
end
