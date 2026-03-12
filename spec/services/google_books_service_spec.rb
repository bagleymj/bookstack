require "rails_helper"

RSpec.describe GoogleBooksService do
  subject(:service) { described_class.new }

  let(:api_url) { "https://www.googleapis.com/books/v1/volumes" }

  def stub_google_books(params: {}, body: {}, status: 200)
    stub_request(:get, api_url)
      .with(query: hash_including(params))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def volume(title:, authors: ["Unknown"], isbn_13: nil, isbn_10: nil, pages: nil, cover: nil, publisher: nil, date: nil, id: nil)
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

  describe "#search_works" do
    it "returns grouped works from search results" do
      stub_google_books(
        params: { q: "meditations" },
        body: {
          "totalItems" => 2,
          "items" => [
            volume(title: "Meditations", authors: ["Marcus Aurelius"], date: "0180", cover: "http://books.google.com/thumb1.jpg"),
            volume(title: "Meditations", authors: ["Marcus Aurelius"], date: "2006", pages: 256)
          ]
        }
      )

      results = service.search_works("meditations")

      expect(results.length).to eq(1) # grouped into one work
      expect(results.first[:title]).to eq("Meditations")
      expect(results.first[:author]).to eq("Marcus Aurelius")
      expect(results.first[:edition_count]).to eq(2)
      expect(results.first[:cover_url]).to eq("https://books.google.com/thumb1.jpg") # http→https
    end

    it "keeps different works separate" do
      stub_google_books(
        params: { q: "meditations" },
        body: {
          "items" => [
            volume(title: "Meditations", authors: ["Marcus Aurelius"]),
            volume(title: "Meditations on First Philosophy", authors: ["Rene Descartes"])
          ]
        }
      )

      results = service.search_works("meditations")

      expect(results.length).to eq(2)
      titles = results.map { |w| w[:title] }
      expect(titles).to include("Meditations", "Meditations on First Philosophy")
    end

    it "applies search_type qualifier for title" do
      stub_google_books(
        params: { q: "intitle:meditations" },
        body: { "items" => [volume(title: "Meditations", authors: ["Marcus Aurelius"])] }
      )

      results = service.search_works("meditations", search_type: "title")

      expect(results.length).to eq(1)
    end

    it "applies search_type qualifier for author" do
      stub_google_books(
        params: { q: "inauthor:aurelius" },
        body: { "items" => [volume(title: "Meditations", authors: ["Marcus Aurelius"])] }
      )

      results = service.search_works("aurelius", search_type: "author")

      expect(results.length).to eq(1)
    end

    it "applies search_type qualifier for isbn" do
      stub_google_books(
        params: { q: "isbn:9780140449334" },
        body: { "items" => [volume(title: "Meditations", authors: ["Marcus Aurelius"], isbn_13: "9780140449334")] }
      )

      results = service.search_works("9780140449334", search_type: "isbn")

      expect(results.length).to eq(1)
    end

    it "respects the limit parameter" do
      items = (1..10).map { |i| volume(title: "Book #{i}", authors: ["Author #{i}"]) }
      stub_google_books(params: { q: "many" }, body: { "items" => items })

      results = service.search_works("many", limit: 3)

      expect(results.length).to eq(3)
    end

    it "returns empty array for blank query" do
      expect(service.search_works("")).to eq([])
      expect(service.search_works(nil)).to eq([])
    end

    it "returns empty array on API error" do
      stub_google_books(params: { q: "test" }, status: 500, body: "error")

      expect(service.search_works("test")).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "slow"))
        .to_timeout

      expect(service.search_works("slow")).to eq([])
    end

    it "returns empty array when no items" do
      stub_google_books(params: { q: "nothing" }, body: { "totalItems" => 0 })

      expect(service.search_works("nothing")).to eq([])
    end

    it "extracts first_publish_year from publishedDate" do
      stub_google_books(
        params: { q: "test" },
        body: { "items" => [volume(title: "Test", date: "2006-03-15")] }
      )

      results = service.search_works("test")
      expect(results.first[:first_publish_year]).to eq("2006")
    end

    it "constructs work key as title|||author" do
      stub_google_books(
        params: { q: "test" },
        body: { "items" => [volume(title: "My Book", authors: ["Jane Doe"])] }
      )

      results = service.search_works("test")
      expect(results.first[:key]).to eq("My Book|||Jane Doe")
    end
  end

  describe "#fetch_editions" do
    it "returns normalized editions for a work key" do
      stub_google_books(
        params: { q: 'intitle:"Meditations"+inauthor:"Marcus Aurelius"' },
        body: {
          "items" => [
            volume(
              title: "Meditations", authors: ["Marcus Aurelius"],
              publisher: "Penguin Classics", date: "2006",
              pages: 256, isbn_13: "9780140449334",
              cover: "https://books.google.com/thumb.jpg", id: "abc123"
            )
          ]
        }
      )

      editions = service.fetch_editions("Meditations|||Marcus Aurelius")

      expect(editions.length).to eq(1)
      expect(editions.first[:title]).to eq("Meditations")
      expect(editions.first[:publisher]).to eq("Penguin Classics")
      expect(editions.first[:year]).to eq("2006")
      expect(editions.first[:pages]).to eq(256)
      expect(editions.first[:isbn]).to eq("9780140449334")
      expect(editions.first[:cover_url]).to eq("https://books.google.com/thumb.jpg")
      expect(editions.first[:key]).to eq("abc123")
    end

    it "deduplicates editions by ISBN" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [
            volume(title: "Test", isbn_13: "9780140449334", pages: 256, id: "v1"),
            volume(title: "Test", isbn_13: "9780140449334", pages: 256, id: "v2"),
            volume(title: "Test", isbn_13: "9780199573202", pages: 192, id: "v3")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")

      isbns = editions.map { |e| e[:isbn] }
      expect(isbns.count("9780140449334")).to eq(1)
      expect(isbns).to include("9780199573202")
    end

    it "prefers ISBN_13 over ISBN_10" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [
            volume(title: "Test", isbn_13: "9780140449334", isbn_10: "0140449334", pages: 100)
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.first[:isbn]).to eq("9780140449334")
    end

    it "falls back to ISBN_10 when ISBN_13 is missing" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [volume(title: "Test", isbn_10: "0199573204", pages: 100)]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.first[:isbn]).to eq("0199573204")
    end

    it "includes editions even when missing pages and isbn" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [
            volume(title: "Has Both", isbn_13: "9780140449334", pages: 256),
            volume(title: "Pages Only", pages: 100),
            volume(title: "ISBN Only", isbn_13: "9780199573202"),
            volume(title: "Neither")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")

      titles = editions.map { |e| e[:title] }
      expect(titles).to include("Has Both", "Pages Only", "ISBN Only", "Neither")
    end

    it "ranks editions with more metadata higher" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [
            volume(title: "Sparse", isbn_10: "1111111111"),
            volume(title: "Complete", publisher: "Great Publisher", date: "2020", pages: 300, isbn_13: "9781234567890", cover: "https://img.jpg")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")

      expect(editions.first[:title]).to eq("Complete")
      expect(editions.last[:title]).to eq("Sparse")
    end

    it "returns empty array for blank work_key" do
      expect(service.fetch_editions("")).to eq([])
      expect(service.fetch_editions(nil)).to eq([])
    end

    it "returns empty array on API error" do
      stub_google_books(params: { q: 'intitle:"Test"+inauthor:"Author"' }, status: 503, body: "error")

      expect(service.fetch_editions("Test|||Author")).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: 'intitle:"Test"+inauthor:"Author"'))
        .to_timeout

      expect(service.fetch_editions("Test|||Author")).to eq([])
    end

    it "works with title-only work key (no author)" do
      stub_google_books(
        params: { q: 'intitle:"Meditations"' },
        body: { "items" => [volume(title: "Meditations", pages: 200)] }
      )

      editions = service.fetch_editions("Meditations|||")

      expect(editions.length).to eq(1)
    end

    it "forces https on cover URLs" do
      stub_google_books(
        params: { q: 'intitle:"Test"+inauthor:"Author"' },
        body: {
          "items" => [
            volume(title: "Test", pages: 100, cover: "http://books.google.com/thumb.jpg")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.first[:cover_url]).to start_with("https://")
    end
  end
end
