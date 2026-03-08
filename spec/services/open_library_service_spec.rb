require "rails_helper"

RSpec.describe OpenLibraryService do
  subject(:service) { described_class.new }

  describe "#search_works" do
    let(:search_url) { "https://openlibrary.org/search.json" }

    it "returns normalized work hashes sorted by score" do
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
            },
            {
              key: "/works/OL99999W",
              title: "Meditations on First Philosophy",
              author_name: ["Rene Descartes"],
              first_publish_year: 1641,
              edition_count: 50,
              cover_i: nil
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      results = service.search_works("meditations")

      expect(results.length).to eq(2)
      # Higher edition count + cover should rank first
      expect(results.first[:key]).to eq("/works/OL55847W")
      expect(results.first[:title]).to eq("Meditations")
      expect(results.first[:author]).to eq("Marcus Aurelius")
      expect(results.first[:first_publish_year]).to eq(180)
      expect(results.first[:edition_count]).to eq(642)
      expect(results.first[:cover_url]).to eq("https://covers.openlibrary.org/b/id/12345-M.jpg")
    end

    it "filters out works with 0 editions" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "obscure"))
        .to_return(status: 200, body: {
          docs: [
            { key: "/works/OL1W", title: "Real Book", edition_count: 5 },
            { key: "/works/OL2W", title: "No Editions", edition_count: 0 }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      results = service.search_works("obscure")

      expect(results.length).to eq(1)
      expect(results.first[:title]).to eq("Real Book")
    end

    it "respects the limit parameter" do
      docs = (1..10).map do |i|
        { key: "/works/OL#{i}W", title: "Book #{i}", edition_count: i }
      end

      stub_request(:get, search_url)
        .with(query: hash_including(q: "many books"))
        .to_return(status: 200, body: { docs: docs }.to_json,
                   headers: { "Content-Type" => "application/json" })

      results = service.search_works("many books", limit: 3)

      expect(results.length).to eq(3)
    end

    it "returns empty array for blank query" do
      results = service.search_works("")

      expect(results).to eq([])
      expect(WebMock).not_to have_requested(:get, search_url)
    end

    it "returns empty array for nil query" do
      results = service.search_works(nil)

      expect(results).to eq([])
    end

    it "returns empty array on API error" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "test"))
        .to_return(status: 500, body: "Internal Server Error")

      results = service.search_works("test")

      expect(results).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "slow"))
        .to_timeout

      results = service.search_works("slow")

      expect(results).to eq([])
    end

    it "returns empty array when API returns no docs" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "nonexistent"))
        .to_return(status: 200, body: { docs: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      results = service.search_works("nonexistent")

      expect(results).to eq([])
    end

    it "handles works with missing optional fields" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "minimal"))
        .to_return(status: 200, body: {
          docs: [
            { key: "/works/OL1W", title: "Minimal Book", edition_count: 1 }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      results = service.search_works("minimal")

      expect(results.length).to eq(1)
      expect(results.first[:title]).to eq("Minimal Book")
      expect(results.first[:author]).to be_nil
      expect(results.first[:first_publish_year]).to be_nil
      expect(results.first[:cover_url]).to be_nil
    end

    it "takes the first author when multiple are listed" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "collab"))
        .to_return(status: 200, body: {
          docs: [
            {
              key: "/works/OL1W", title: "Collaboration",
              author_name: ["First Author", "Second Author"],
              edition_count: 3
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      results = service.search_works("collab")

      expect(results.first[:author]).to eq("First Author")
    end

    it "ranks works with covers higher than those without" do
      stub_request(:get, search_url)
        .with(query: hash_including(q: "covers"))
        .to_return(status: 200, body: {
          docs: [
            { key: "/works/OL1W", title: "No Cover", edition_count: 10, cover_i: nil },
            { key: "/works/OL2W", title: "Has Cover", edition_count: 10, cover_i: 99999 }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      results = service.search_works("covers")

      expect(results.first[:title]).to eq("Has Cover")
    end
  end

  describe "#fetch_editions" do
    let(:editions_url) { "https://openlibrary.org/works/OL55847W/editions.json" }

    it "returns normalized edition hashes sorted by score" do
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
            },
            {
              key: "/books/OL5678M",
              title: "Meditations",
              publishers: ["Oxford University Press"],
              publish_date: "March 2011",
              number_of_pages: 192,
              isbn_10: ["0199573204"],
              physical_format: "hardcover",
              covers: nil
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.length).to eq(2)
      # Penguin edition has cover + isbn_13 + all fields -> higher score
      penguin = editions.find { |e| e[:key] == "/books/OL1234M" }
      expect(penguin[:title]).to eq("Meditations")
      expect(penguin[:publisher]).to eq("Penguin Classics")
      expect(penguin[:year]).to eq("2006")
      expect(penguin[:pages]).to eq(256)
      expect(penguin[:isbn]).to eq("9780140449334")
      expect(penguin[:format]).to eq("Paperback")
      expect(penguin[:cover_url]).to eq("https://covers.openlibrary.org/b/id/67890-M.jpg")
    end

    it "handles bare work ID without /works/ prefix" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: { entries: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("OL55847W")

      expect(editions).to eq([])
      expect(WebMock).to have_requested(:get, editions_url).with(query: hash_including(limit: "100"))
    end

    it "filters out editions missing both pages and isbn" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Good Edition",
              number_of_pages: 200,
              isbn_13: ["9781234567890"]
            },
            {
              key: "/books/OL2M",
              title: "Pages Only",
              number_of_pages: 150
            },
            {
              key: "/books/OL3M",
              title: "ISBN Only",
              isbn_10: ["1234567890"]
            },
            {
              key: "/books/OL4M",
              title: "Sparse Edition"
              # no pages, no isbn
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.length).to eq(3)
      keys = editions.map { |e| e[:key] }
      expect(keys).to include("/books/OL1M", "/books/OL2M", "/books/OL3M")
      expect(keys).not_to include("/books/OL4M")
    end

    it "prefers isbn_13 over isbn_10" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Both ISBNs",
              isbn_13: ["9781234567890"],
              isbn_10: ["1234567890"],
              number_of_pages: 100
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.first[:isbn]).to eq("9781234567890")
    end

    it "falls back to isbn_10 when isbn_13 is missing" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "ISBN 10 Only",
              isbn_10: ["0199573204"],
              number_of_pages: 100
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.first[:isbn]).to eq("0199573204")
    end

    it "extracts year from various publish_date formats" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            { key: "/books/OL1M", title: "A", publish_date: "2006", number_of_pages: 100 },
            { key: "/books/OL2M", title: "B", publish_date: "March 2011", number_of_pages: 100 },
            { key: "/books/OL3M", title: "C", publish_date: "Mar 15, 2020", number_of_pages: 100 },
            { key: "/books/OL4M", title: "D", publish_date: nil, number_of_pages: 100 }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      years = editions.map { |e| [e[:key], e[:year]] }.to_h
      expect(years["/books/OL1M"]).to eq("2006")
      expect(years["/books/OL2M"]).to eq("2011")
      expect(years["/books/OL3M"]).to eq("2020")
      expect(years["/books/OL4M"]).to be_nil
    end

    it "returns empty array for blank work_key" do
      editions = service.fetch_editions("")

      expect(editions).to eq([])
    end

    it "returns empty array on API error" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 503, body: "Service Unavailable")

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_timeout

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions).to eq([])
    end

    it "ranks editions with more metadata higher" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Sparse",
              isbn_10: ["1111111111"]
              # no pages, no cover, no publisher, no year, no format
            },
            {
              key: "/books/OL2M",
              title: "Complete",
              publishers: ["Great Publisher"],
              publish_date: "2020",
              number_of_pages: 300,
              isbn_13: ["9781234567890"],
              physical_format: "paperback",
              covers: [11111]
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.first[:key]).to eq("/books/OL2M")
      expect(editions.last[:key]).to eq("/books/OL1M")
    end

    it "capitalizes the physical_format field" do
      stub_request(:get, editions_url)
        .with(query: hash_including(limit: "100"))
        .to_return(status: 200, body: {
          entries: [
            {
              key: "/books/OL1M",
              title: "Test",
              physical_format: "paperback",
              number_of_pages: 100
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      editions = service.fetch_editions("/works/OL55847W")

      expect(editions.first[:format]).to eq("Paperback")
    end
  end
end
