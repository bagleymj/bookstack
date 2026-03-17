require "csv"

class GoodreadsImportService
  # Goodreads exclusive shelf → BookStack status
  SHELF_TO_STATUS = {
    "to-read" => :unread,
    "currently-reading" => :reading,
    "read" => :completed
  }.freeze

  Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

  def initialize(user)
    @user = user
  end

  # Parse a Goodreads CSV export and return an array of hashes suitable for preview.
  # Each hash contains the raw Goodreads data plus the mapped BookStack fields.
  def parse(csv_content)
    rows = CSV.parse(csv_content, headers: true, liberal_parsing: true)
    rows.map { |row| parse_row(row) }.compact
  end

  # Import selected books. +entries+ is an array of hashes (from parse or form params)
  # with keys: title, author, isbn, last_page, status, cover_image_url.
  # Skips books whose ISBN already exists in the user's library.
  def import(entries)
    existing_isbns = @user.books.where.not(isbn: [nil, ""]).pluck(:isbn).to_set
    imported = []
    skipped = []
    errors = []

    entries.each do |entry|
      isbn = entry[:isbn].presence

      if isbn && existing_isbns.include?(isbn)
        skipped << entry.merge(reason: "ISBN already in library")
        next
      end

      book = @user.books.build(
        title: entry[:title],
        author: entry[:author],
        isbn: isbn,
        first_page: 1,
        last_page: entry[:last_page].presence&.to_i || 300,
        status: entry[:status] || :unread,
        density: :average,
        owned: false
      )

      if book.save
        imported << book
        existing_isbns << isbn if isbn
      else
        errors << entry.merge(reason: book.errors.full_messages.join(", "))
      end
    end

    Result.new(imported: imported, skipped: skipped, errors: errors)
  end

  private

  def parse_row(row)
    title = row["Title"]&.strip
    return nil if title.blank?

    last_page = row["Number of Pages"]&.strip&.to_i
    last_page = nil if last_page&.zero?

    {
      goodreads_id: row["Book Id"]&.strip,
      title: title,
      author: row["Author"]&.strip,
      additional_authors: row["Additional Authors"]&.strip,
      isbn: clean_isbn(row["ISBN13"].presence || row["ISBN"]),
      last_page: last_page,
      exclusive_shelf: row["Exclusive Shelf"]&.strip,
      status: SHELF_TO_STATUS[row["Exclusive Shelf"]&.strip] || :unread,
      my_rating: row["My Rating"]&.strip&.to_i,
      average_rating: row["Average Rating"]&.strip,
      publisher: row["Publisher"]&.strip,
      binding: row["Binding"]&.strip,
      year_published: row["Year Published"]&.strip,
      date_read: row["Date Read"]&.strip,
      date_added: row["Date Added"]&.strip,
      bookshelves: row["Bookshelves"]&.strip,
      cover_image_url: nil
    }
  end

  # Goodreads wraps ISBNs in ="VALUE" to prevent Excel number coercion
  def clean_isbn(raw)
    return nil if raw.blank?
    raw.strip.gsub(/\A="?|"?\z/, "").presence
  end
end
