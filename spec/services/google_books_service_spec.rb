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

    it "includes volume_ids from grouped volumes" do
      stub_google_books(
        params: { q: "meditations" },
        body: {
          "items" => [
            volume(title: "Meditations", authors: ["Marcus Aurelius"], id: "vol_1"),
            volume(title: "Meditations", authors: ["Marcus Aurelius"], id: "vol_2"),
            volume(title: "Meditations", authors: ["Marcus Aurelius"], id: "vol_3")
          ]
        }
      )

      results = service.search_works("meditations")
      expect(results.first[:volume_ids]).to contain_exactly("vol_1", "vol_2", "vol_3")
    end
  end

  describe "#fetch_editions" do
    it "returns normalized editions for a work key" do
      stub_google_books(
        params: { q: "intitle:Meditations+inauthor:Marcus Aurelius" },
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
        params: { q: "intitle:Test+inauthor:Author" },
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
        params: { q: "intitle:Test+inauthor:Author" },
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
        params: { q: "intitle:Test+inauthor:Author" },
        body: {
          "items" => [volume(title: "Test", isbn_10: "0199573204", pages: 100)]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.first[:isbn]).to eq("0199573204")
    end

    it "includes editions even when missing pages and isbn" do
      stub_google_books(
        params: { q: "intitle:Test+inauthor:Author" },
        body: {
          "items" => [
            volume(title: "Test", isbn_13: "9780140449334", pages: 256),
            volume(title: "Test", pages: 100),
            volume(title: "Test", isbn_13: "9780199573202"),
            volume(title: "Test")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.length).to eq(4)
    end

    it "filters out editions with non-matching titles" do
      stub_google_books(
        params: { q: "intitle:Nature and Selected Essays+inauthor:Emerson" },
        body: {
          "items" => [
            volume(title: "Nature and Selected Essays", pages: 300, isbn_13: "9780140449334"),
            volume(title: "Nature and Selected Essays: Penguin Edition", pages: 320),
            volume(title: "The Nature of Things", pages: 200),
            volume(title: "Selected Essays on Art", pages: 150)
          ]
        }
      )

      editions = service.fetch_editions("Nature and Selected Essays|||Emerson")

      titles = editions.map { |e| e[:title] }
      expect(titles).to include("Nature and Selected Essays")
      expect(titles).to include("Nature and Selected Essays: Penguin Edition")
      expect(titles).not_to include("The Nature of Things")
      expect(titles).not_to include("Selected Essays on Art")
    end

    it "ranks editions with more metadata higher" do
      stub_google_books(
        params: { q: "intitle:Test+inauthor:Author" },
        body: {
          "items" => [
            volume(title: "Test", isbn_10: "1111111111"),
            volume(title: "Test", publisher: "Great Publisher", date: "2020", pages: 300, isbn_13: "9781234567890", cover: "https://img.jpg")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")

      expect(editions.first[:publisher]).to eq("Great Publisher")
      expect(editions.last[:isbn]).to eq("1111111111")
    end

    it "returns empty array for blank work_key" do
      expect(service.fetch_editions("")).to eq([])
      expect(service.fetch_editions(nil)).to eq([])
    end

    it "returns empty array on API error" do
      stub_google_books(params: { q: "intitle:Test+inauthor:Author" }, status: 503, body: "error")

      expect(service.fetch_editions("Test|||Author")).to eq([])
    end

    it "returns empty array on timeout" do
      stub_request(:get, api_url)
        .with(query: hash_including(q: "intitle:Test+inauthor:Author"))
        .to_timeout

      expect(service.fetch_editions("Test|||Author")).to eq([])
    end

    it "works with title-only work key (no author)" do
      stub_google_books(
        params: { q: "intitle:Meditations" },
        body: { "items" => [volume(title: "Meditations", pages: 200)] }
      )

      editions = service.fetch_editions("Meditations|||")

      expect(editions.length).to eq(1)
    end

    it "forces https on cover URLs" do
      stub_google_books(
        params: { q: "intitle:Test+inauthor:Author" },
        body: {
          "items" => [
            volume(title: "Test", pages: 100, cover: "http://books.google.com/thumb.jpg")
          ]
        }
      )

      editions = service.fetch_editions("Test|||Author")
      expect(editions.first[:cover_url]).to start_with("https://")
    end

    context "with seed volume IDs" do
      def stub_volume_by_id(id:, title:, **opts)
        stub_request(:get, "#{api_url}/#{id}")
          .to_return(
            status: 200,
            body: volume(title: title, id: id, **opts).to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches seed volumes by ID and includes them in results" do
        stub_volume_by_id(id: "seed_1", title: "Nature and Selected Essays", pages: 300, isbn_13: "9781111111111")

        # Keyword search returns different results
        stub_google_books(
          params: { q: "intitle:Nature and Selected Essays+inauthor:Emerson" },
          body: {
            "items" => [
              volume(title: "Nature and Selected Essays", publisher: "Createspace", pages: 200, id: "other_1")
            ]
          }
        )

        editions = service.fetch_editions("Nature and Selected Essays|||Emerson", seed_volume_ids: ["seed_1"])

        keys = editions.map { |e| e[:key] }
        expect(keys).to include("seed_1")
        expect(keys).to include("other_1")
      end

      it "deduplicates seed volumes that also appear in search results" do
        stub_volume_by_id(id: "vol_1", title: "Test", pages: 256, isbn_13: "9781111111111")

        stub_google_books(
          params: { q: "intitle:Test+inauthor:Author" },
          body: {
            "items" => [
              volume(title: "Test", pages: 256, isbn_13: "9781111111111", id: "vol_1"),
              volume(title: "Test", pages: 192, isbn_13: "9782222222222", id: "vol_2")
            ]
          }
        )

        editions = service.fetch_editions("Test|||Author", seed_volume_ids: ["vol_1"])

        keys = editions.map { |e| e[:key] }
        expect(keys.count("vol_1")).to eq(1)
        expect(keys).to include("vol_2")
      end

      it "still works when seed volume fetch fails" do
        stub_request(:get, "#{api_url}/bad_id")
          .to_return(status: 404, body: "Not found")

        stub_google_books(
          params: { q: "intitle:Test+inauthor:Author" },
          body: {
            "items" => [volume(title: "Test", pages: 100, id: "v1")]
          }
        )

        editions = service.fetch_editions("Test|||Author", seed_volume_ids: ["bad_id"])
        expect(editions.length).to eq(1)
        expect(editions.first[:key]).to eq("v1")
      end

      it "applies title filtering to seed volumes" do
        stub_volume_by_id(id: "wrong_title", title: "Completely Different Book", pages: 300)

        stub_google_books(
          params: { q: "intitle:Test+inauthor:Author" },
          body: { "items" => [volume(title: "Test", pages: 100, id: "v1")] }
        )

        editions = service.fetch_editions("Test|||Author", seed_volume_ids: ["wrong_title"])

        keys = editions.map { |e| e[:key] }
        expect(keys).not_to include("wrong_title")
        expect(keys).to include("v1")
      end
    end
  end
end
