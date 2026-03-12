require "rails_helper"

RSpec.describe "API V1 BookSearch", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }
  let(:api_url) { "https://www.googleapis.com/books/v1/volumes" }

  before { sign_in user }

  def google_volume(title:, authors: ["Unknown"], isbn_13: nil, isbn_10: nil, pages: nil, cover: nil, publisher: nil, date: nil, id: nil)
    identifiers = []
    identifiers << { "type" => "ISBN_13", "identifier" => isbn_13 } if isbn_13
    identifiers << { "type" => "ISBN_10", "identifier" => isbn_10 } if isbn_10

    image_links = cover ? { "thumbnail" => cover } : nil

    {
      "id" => id || SecureRandom.hex(6),
      "volumeInfo" => {
        "title" => title,
        "authors" => authors,
        "publisher" => publisher,
        "publishedDate" => date,
        "pageCount" => pages,
        "printType" => "BOOK",
        "industryIdentifiers" => identifiers,
        "imageLinks" => image_links
      }.compact
    }
  end

  describe "GET /api/v1/book_search" do
    it "returns works matching the query" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "meditations"))
        .to_return(status: 200, body: {
          "totalItems" => 1,
          "items" => [
            google_volume(title: "Meditations", authors: ["Marcus Aurelius"], date: "0180", cover: "https://books.google.com/thumb.jpg")
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search", params: { q: "meditations" }

      expect(response).to have_http_status(:ok)
      results = json_response["results"]
      expect(results.length).to eq(1)
      expect(results.first["title"]).to eq("Meditations")
      expect(results.first["author"]).to eq("Marcus Aurelius")
      expect(results.first["key"]).to eq("Meditations|||Marcus Aurelius")
    end

    it "passes search_type to the service" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:meditations"))
        .to_return(status: 200, body: {
          "items" => [google_volume(title: "Meditations", authors: ["Marcus Aurelius"])]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search", params: { q: "meditations", search_type: "title" }

      expect(response).to have_http_status(:ok)
      expect(json_response["results"].length).to eq(1)
    end

    it "returns empty results for blank query" do
      get "/api/v1/book_search", params: { q: "" }

      expect(response).to have_http_status(:ok)
      expect(json_response["results"]).to eq([])
    end

    it "returns empty results when query param is missing" do
      get "/api/v1/book_search"

      expect(response).to have_http_status(:ok)
      expect(json_response["results"]).to eq([])
    end

    it "returns empty results when API fails" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "test"))
        .to_return(status: 500, body: "error")

      get "/api/v1/book_search", params: { q: "test" }

      expect(response).to have_http_status(:ok)
      expect(json_response["results"]).to eq([])
    end

    it "requires authentication" do
      sign_out user
      get "/api/v1/book_search", params: { q: "test" }

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /api/v1/book_search/editions" do
    it "returns editions for a work" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Meditations+inauthor:Marcus Aurelius"))
        .to_return(status: 200, body: {
          "items" => [
            google_volume(
              title: "Meditations", authors: ["Marcus Aurelius"],
              publisher: "Penguin Classics", date: "2006",
              pages: 256, isbn_13: "9780140449334",
              cover: "https://books.google.com/thumb.jpg", id: "abc123"
            )
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "Meditations|||Marcus Aurelius" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      expect(editions.length).to eq(1)
      expect(editions.first["publisher"]).to eq("Penguin Classics")
      expect(editions.first["pages"]).to eq(256)
      expect(editions.first["isbn"]).to eq("9780140449334")
    end

    it "returns empty editions for blank work_key" do
      get "/api/v1/book_search/editions", params: { work_key: "" }

      expect(response).to have_http_status(:ok)
      expect(json_response["editions"]).to eq([])
    end

    it "returns empty editions when work_key param is missing" do
      get "/api/v1/book_search/editions"

      expect(response).to have_http_status(:ok)
      expect(json_response["editions"]).to eq([])
    end

    it "marks editions that are already in the user's collection" do
      create(:book, user: user, isbn: "9780140449334")

      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Meditations+inauthor:Marcus Aurelius"))
        .to_return(status: 200, body: {
          "items" => [
            google_volume(title: "Meditations", isbn_13: "9780140449334", pages: 256, id: "v1"),
            google_volume(title: "Meditations", isbn_13: "9780199573202", pages: 192, id: "v2")
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "Meditations|||Marcus Aurelius" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      owned = editions.find { |e| e["isbn"] == "9780140449334" }
      not_owned = editions.find { |e| e["isbn"] == "9780199573202" }
      expect(owned["in_collection"]).to be true
      expect(not_owned["in_collection"]).to be false
    end

    it "overlays local edition cache data" do
      create(:edition, isbn: "9780140449334", recommended_first_page: 5, recommended_last_page: 240)

      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Test+inauthor:Author"))
        .to_return(status: 200, body: {
          "items" => [
            google_volume(title: "Test", isbn_13: "9780140449334", pages: 256, id: "v1")
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "Test|||Author" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      expect(editions.first["recommended_first_page"]).to eq(5)
      expect(editions.first["recommended_last_page"]).to eq(240)
      expect(editions.first["has_local_data"]).to be true
    end

    it "does not mark editions without isbn as in_collection" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Test+inauthor:Author"))
        .to_return(status: 200, body: {
          "items" => [
            google_volume(title: "Test", pages: 256, id: "v1")
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "Test|||Author" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      expect(editions.first["in_collection"]).to be false
    end

    it "passes seed volume IDs to the service" do
      stub_request(:get, "#{api_url}/seed_vol_1")
        .to_return(status: 200, body: google_volume(
          title: "Meditations", pages: 300, isbn_13: "9783333333333", id: "seed_vol_1"
        ).to_json, headers: { "Content-Type" => "application/json" })

      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Meditations+inauthor:Marcus Aurelius"))
        .to_return(status: 200, body: {
          "items" => [
            google_volume(title: "Meditations", isbn_13: "9780140449334", pages: 256, id: "v1")
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: {
        work_key: "Meditations|||Marcus Aurelius",
        volume_ids: ["seed_vol_1"]
      }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      keys = editions.map { |e| e["key"] }
      expect(keys).to include("seed_vol_1")
      expect(keys).to include("v1")
    end

    it "requires authentication" do
      sign_out user
      get "/api/v1/book_search/editions", params: { work_key: "Test|||Author" }

      expect(response).to have_http_status(:redirect)
    end
  end
end
