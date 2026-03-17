require "rails_helper"

RSpec.describe GoodreadsExportService do
  let(:user) { create(:user) }
  subject(:service) { described_class.new(user) }

  describe "#generate" do
    it "generates a valid CSV with Goodreads headers" do
      create(:book, user: user, title: "Meditations", author: "Marcus Aurelius",
             isbn: "9780140449334", last_page: 256, status: :unread)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.headers).to include("Title", "Author", "ISBN13", "Exclusive Shelf", "Number of Pages")
      expect(parsed.size).to eq(1)
    end

    it "maps BookStack statuses to Goodreads shelves" do
      create(:book, :unread, user: user, title: "Unread Book", last_page: 200)
      create(:book, :reading, user: user, title: "Reading Book", last_page: 300)
      create(:book, :completed, user: user, title: "Completed Book", last_page: 250)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      shelves = parsed.map { |row| [row["Title"], row["Exclusive Shelf"]] }.to_h
      expect(shelves["Completed Book"]).to eq("read")
      expect(shelves["Reading Book"]).to eq("currently-reading")
      expect(shelves["Unread Book"]).to eq("to-read")
    end

    it "formats ISBN in Goodreads =\"VALUE\" format" do
      create(:book, user: user, title: "Test", isbn: "9780140449334", last_page: 256)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.first["ISBN13"]).to eq('="9780140449334"')
    end

    it "formats author in last-first format" do
      create(:book, user: user, title: "Test", author: "Marcus Aurelius", last_page: 256)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.first["Author"]).to eq("Marcus Aurelius")
      expect(parsed.first["Author l-f"]).to eq("Aurelius, Marcus")
    end

    it "includes date read for completed books" do
      completed_at = Time.zone.parse("2025-06-15 12:00:00")
      create(:book, :completed, user: user, title: "Done", last_page: 200, completed_at: completed_at)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.first["Date Read"]).to eq("2025/06/15")
    end

    it "sets read count to 1 for completed books and 0 for others" do
      create(:book, :completed, user: user, title: "Done", last_page: 200)
      create(:book, :unread, user: user, title: "Not Done", last_page: 200)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      read_counts = parsed.map { |row| [row["Title"], row["Read Count"]] }.to_h
      expect(read_counts["Done"]).to eq("1")
      expect(read_counts["Not Done"]).to eq("0")
    end

    it "exports only books with the specified status" do
      create(:book, :unread, user: user, title: "Unread", last_page: 200)
      create(:book, :completed, user: user, title: "Done", last_page: 200)

      books = user.books.where(status: :unread)
      csv = service.generate(books)
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.size).to eq(1)
      expect(parsed.first["Title"]).to eq("Unread")
    end

    it "includes all 31 Goodreads columns" do
      create(:book, user: user, title: "Test", last_page: 200)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.headers.size).to eq(31)
    end

    it "handles books without ISBN gracefully" do
      create(:book, user: user, title: "No ISBN", isbn: nil, last_page: 200)

      csv = service.generate
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.first["ISBN13"]).to eq("")
    end
  end
end
