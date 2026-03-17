require "rails_helper"

RSpec.describe GoodreadsImportService do
  let(:user) { create(:user) }
  subject(:service) { described_class.new(user) }

  describe "#parse" do
    it "parses a standard Goodreads CSV export" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        12345,Meditations,Marcus Aurelius,"Aurelius, Marcus",,="0140449337",="9780140449334",0,4.25,Penguin Classics,Paperback,256,2006,180,,2024/01/15,,,to-read,,,,0,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries.size).to eq(1)

      entry = entries.first
      expect(entry[:title]).to eq("Meditations")
      expect(entry[:author]).to eq("Marcus Aurelius")
      expect(entry[:isbn]).to eq("9780140449334")
      expect(entry[:last_page]).to eq(256)
      expect(entry[:exclusive_shelf]).to eq("to-read")
      expect(entry[:status]).to eq(:unread)
    end

    it "maps Goodreads shelves to BookStack statuses" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Book A,Author A,"A, Author",,,,0,0,,,,,,,,,,to-read,,,,0,,,,,,,,
        2,Book B,Author B,"B, Author",,,,0,0,,,,,,,,,,currently-reading,,,,0,,,,,,,,
        3,Book C,Author C,"C, Author",,,,0,0,,,,,,,,,,read,,,,1,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries.map { |e| e[:status] }).to eq([:unread, :reading, :completed])
    end

    it "cleans ISBN from Goodreads =\"VALUE\" format" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Test Book,Test Author,"Author, Test",,="0140449337",="9780140449334",0,0,,,,,,,,,,to-read,,,,0,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries.first[:isbn]).to eq("9780140449334")
    end

    it "falls back to ISBN-10 when ISBN-13 is empty" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Test Book,Test Author,"Author, Test",,"0140449337",,0,0,,,,,,,,,,to-read,,,,0,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries.first[:isbn]).to eq("0140449337")
    end

    it "skips rows with blank titles" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,,Test Author,"Author, Test",,,,0,0,,,,,,,,,,to-read,,,,0,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries).to be_empty
    end

    it "handles missing page count gracefully" do
      csv = <<~CSV
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
        1,Test Book,Test Author,"Author, Test",,,,0,0,,,,,,,,,,,,,0,,,,,,,,
      CSV

      entries = service.parse(csv)
      expect(entries.first[:last_page]).to be_nil
    end
  end

  describe "#import" do
    it "creates books from entries" do
      entries = [
        { title: "Meditations", author: "Marcus Aurelius", isbn: "9780140449334", last_page: 256, status: :unread }
      ]

      result = service.import(entries)
      expect(result.imported.size).to eq(1)
      expect(result.skipped).to be_empty
      expect(result.errors).to be_empty

      book = result.imported.first
      expect(book.title).to eq("Meditations")
      expect(book.author).to eq("Marcus Aurelius")
      expect(book.isbn).to eq("9780140449334")
      expect(book.last_page).to eq(256)
      expect(book.first_page).to eq(1)
      expect(book.unread?).to be true
      expect(book.owned?).to be false
    end

    it "skips books whose ISBN already exists in the user's library" do
      create(:book, user: user, isbn: "9780140449334", last_page: 256)

      entries = [
        { title: "Meditations", author: "Marcus Aurelius", isbn: "9780140449334", last_page: 256, status: :unread }
      ]

      result = service.import(entries)
      expect(result.imported).to be_empty
      expect(result.skipped.size).to eq(1)
      expect(result.skipped.first[:reason]).to include("already in library")
    end

    it "imports books without ISBN even when duplicates exist" do
      entries = [
        { title: "Book A", author: "Author A", isbn: nil, last_page: 200, status: :unread },
        { title: "Book B", author: "Author B", isbn: "", last_page: 300, status: :reading }
      ]

      result = service.import(entries)
      expect(result.imported.size).to eq(2)
    end

    it "defaults to 300 pages when last_page is missing" do
      entries = [
        { title: "Unknown Length", author: "Author", isbn: nil, last_page: nil, status: :unread }
      ]

      result = service.import(entries)
      expect(result.imported.first.last_page).to eq(300)
    end

    it "reports validation errors without stopping the batch" do
      entries = [
        { title: "Good Book", author: "Author", isbn: nil, last_page: 200, status: :unread },
        { title: "", author: "No Title", isbn: nil, last_page: 200, status: :unread },
        { title: "Another Good Book", author: "Author 2", isbn: nil, last_page: 150, status: :unread }
      ]

      result = service.import(entries)
      expect(result.imported.size).to eq(2)
      expect(result.errors.size).to eq(1)
    end
  end
end
