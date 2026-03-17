require "csv"

class GoodreadsExportService
  # BookStack status → Goodreads exclusive shelf
  STATUS_TO_SHELF = {
    "unread" => "to-read",
    "reading" => "currently-reading",
    "completed" => "read",
    "abandoned" => "read"
  }.freeze

  HEADERS = [
    "Book Id", "Title", "Author", "Author l-f", "Additional Authors",
    "ISBN", "ISBN13", "My Rating", "Average Rating", "Publisher",
    "Binding", "Number of Pages", "Year Published", "Original Publication Year",
    "Date Read", "Date Added", "Bookshelves", "Bookshelves with positions",
    "Exclusive Shelf", "My Review", "Spoiler", "Private Notes",
    "Read Count", "Recommended For", "Recommended By", "Owned Copies",
    "Original Purchase Date", "Original Purchase Location", "Condition",
    "Condition Description", "BCID"
  ].freeze

  def initialize(user)
    @user = user
  end

  # Generate a Goodreads-compatible CSV string for the given books.
  # If no books provided, exports all of the user's books.
  def generate(books = nil)
    books ||= @user.books.order(:title)

    CSV.generate do |csv|
      csv << HEADERS
      books.each { |book| csv << book_to_row(book) }
    end
  end

  private

  def book_to_row(book)
    shelf = STATUS_TO_SHELF[book.status] || "to-read"
    author_lf = author_last_first(book.author)
    isbn13 = book.isbn.present? ? format_isbn(book.isbn) : ""
    date_read = book.completed_at&.strftime("%Y/%m/%d") || ""
    date_added = book.created_at&.strftime("%Y/%m/%d") || ""
    read_count = book.completed? ? 1 : 0
    owned_copies = book.owned? ? 1 : 0

    [
      "",             # Book Id (Goodreads internal — leave blank)
      book.title,
      book.author || "",
      author_lf,
      "",             # Additional Authors
      "",             # ISBN (10-digit — we only store 13)
      isbn13,
      0,              # My Rating (not tracked in BookStack)
      "",             # Average Rating
      "",             # Publisher
      "",             # Binding
      book.total_pages,
      "",             # Year Published
      "",             # Original Publication Year
      date_read,
      date_added,
      shelf,          # Bookshelves
      "",             # Bookshelves with positions
      shelf,          # Exclusive Shelf
      "",             # My Review
      "",             # Spoiler
      "",             # Private Notes
      read_count,
      "",             # Recommended For
      "",             # Recommended By
      owned_copies,
      "",             # Original Purchase Date
      "",             # Original Purchase Location
      "",             # Condition
      "",             # Condition Description
      ""              # BCID
    ]
  end

  def author_last_first(author)
    return "" if author.blank?
    parts = author.strip.split(/\s+/)
    return author if parts.size <= 1
    "#{parts.last}, #{parts[0..-2].join(' ')}"
  end

  # Goodreads expects ISBNs in ="VALUE" format to prevent Excel number coercion
  def format_isbn(isbn)
    return "" if isbn.blank?
    %Q(="#{isbn}")
  end
end
