require "rails_helper"

RSpec.describe "API V1 BookSearch", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }
  let(:search_url) { "https://openlibrary.org/search.json" }

  before { sign_in user }

  describe "GET /api/v1/book_search" do
    it "returns works matching the query" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "meditations"))
        .to_return(status: 200, body: {
          docs: [
            {
              key: "/works/OL55847W",
              title: "Meditations",
              author_name: ["Marcus Aurelius"],
              first_publish_year: 180,
              edition_count: 642,
              cover_i: 12345
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search", params: { q: "meditations" }

      expect(response).to have_http_status(:ok)
      results = json_response["results"]
      expect(results.length).to eq(1)
      expect(results.first["key"]).to eq("/works/OL55847W")
      expect(results.first["title"]).to eq("Meditations")
      expect(results.first["author"]).to eq("Marcus Aurelius")
      expect(results.first["edition_count"]).to eq(642)
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
      stub_request(:get, search_url)
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
    let(:editions_url) { "https://openlibrary.org/works/OL55847W/editions.json" }

    it "returns editions for a work" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1234M",
              title: "Meditations",
              publishers: ["Penguin Classics"],
              publish_date: "2006",
              number_of_pages: 256,
              isbn_13: ["9780140449334"],
              physical_format: "paperback",
              covers: [67890]
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "/works/OL55847W" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      expect(editions.length).to eq(1)
      expect(editions.first["publisher"]).to eq("Penguin Classics")
      expect(editions.first["pages"]).to eq(256)
      expect(editions.first["isbn"]).to eq("9780140449334")
      expect(editions.first["format"]).to eq("Paperback")
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

      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Meditations",
              isbn_13: ["9780140449334"],
              number_of_pages: 256
            },
            {
              key: "/books/OL2M",
              title: "Meditations",
              isbn_13: ["9780199573202"],
              number_of_pages: 192
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "/works/OL55847W" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      owned = editions.find { |e| e["isbn"] == "9780140449334" }
      not_owned = editions.find { |e| e["isbn"] == "9780199573202" }
      expect(owned["in_collection"]).to be true
      expect(not_owned["in_collection"]).to be false
    end

    it "does not mark editions without isbn as in_collection" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Meditations",
              number_of_pages: 256
              # no isbn
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      get "/api/v1/book_search/editions", params: { work_key: "/works/OL55847W" }

      expect(response).to have_http_status(:ok)
      editions = json_response["editions"]
      expect(editions.first["in_collection"]).to be false
    end

    it "requires authentication" do
      sign_out user
      get "/api/v1/book_search/editions", params: { work_key: "/works/OL55847W" }

      expect(response).to have_http_status(:redirect)
    end
  end
end
