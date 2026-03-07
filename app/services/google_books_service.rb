require "net/http"
require "json"

class GoogleBooksService
  BASE_URL = "https://www.googleapis.com"
  TIMEOUT = 5 # seconds

  class ApiError < StandardError; end

  # Search for books by title/author query
  # Supports "by Author Name" prefix for explicit author search.
  # Also auto-detects initials (e.g. "C.S. Lewis") as author searches.
  def search(query, limit: 8)
    return [] if query.blank?

    author_mode, clean_query = detect_author_search(query)
    search_query = author_mode ? "inauthor:#{clean_query}" : clean_query

    # Request extra results for author searches since we'll post-filter
    api_limit = author_mode ? [limit * 3, 40].min : limit

    params = {
      q: search_query,
      maxResults: api_limit,
      printType: "books"
    }

    add_api_key(params)

    response = get("/books/v1/volumes", params)
    items = response["items"] || []

    results = items.map { |item| normalize(item) }.compact

    if author_mode
      results = filter_by_author(results, clean_query)
    end

    results.first(limit)
  rescue ApiError, Net::TimeoutError, JSON::ParserError => e
    Rails.logger.error("GoogleBooks search error: #{e.message}")
    []
  end

  # Fetch a single book by ISBN
  # Returns normalized book hash or nil
  def fetch_by_isbn(isbn)
    return nil if isbn.blank?

    clean_isbn = isbn.to_s.gsub(/[-\s]/, "")

    params = {
      q: "isbn:#{clean_isbn}",
      maxResults: 1
    }

    add_api_key(params)

    response = get("/books/v1/volumes", params)
    item = response.dig("items", 0)
    return nil unless item

    normalize(item)
  rescue ApiError, Net::TimeoutError, JSON::ParserError => e
    Rails.logger.error("GoogleBooks ISBN lookup error: #{e.message}")
    nil
  end

  private

  def get(path, params = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params.any?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "BookStack/1.0 (Reading Goal Tracker)"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "HTTP #{response.code}: #{response.message}"
    end

    JSON.parse(response.body)
  end

  def normalize(item)
    info = item["volumeInfo"]
    return nil unless info && info["title"].present?

    {
      title: info["title"],
      author: info["authors"]&.join(", "),
      year: info["publishedDate"]&.slice(0, 4),
      pages: info["pageCount"],
      isbn: extract_isbn13(info["industryIdentifiers"]) || extract_isbn10(info["industryIdentifiers"]),
      cover_url: info.dig("imageLinks", "thumbnail")&.sub("http://", "https://"),
      cover_url_small: info.dig("imageLinks", "smallThumbnail")&.sub("http://", "https://"),
      publisher: info["publisher"],
      google_books_id: item["id"]
    }
  end

  def extract_isbn13(identifiers)
    return nil unless identifiers

    identifiers.find { |id| id["type"] == "ISBN_13" }&.dig("identifier")
  end

  def extract_isbn10(identifiers)
    return nil unless identifiers

    identifiers.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")
  end

  def add_api_key(params)
    api_key = Rails.application.credentials.dig(:google_books, :api_key)
    params[:key] = api_key if api_key.present?
  end

  # Detect whether the query is an author search.
  # Returns [author_mode, cleaned_query].
  #
  # Triggers on:
  #   - Explicit "by " prefix: "by David McCullough" → author search for "David McCullough"
  #   - Initials pattern: "C.S. Lewis", "J.R.R. Tolkien" → unambiguously author names
  def detect_author_search(query)
    stripped = query.strip

    # Explicit "by " prefix
    if stripped.match?(/\Aby\s+/i)
      return [true, stripped.sub(/\Aby\s+/i, "")]
    end

    # Query contains initials like "C.S." or "J.K." or "J.R.R."
    words = stripped.split(/\s+/)
    if words.length >= 2 && words.any? { |w| w.match?(/\A([A-Z]\.){1,3}\z/) }
      return [true, stripped]
    end

    [false, stripped]
  end

  # Keep only results where the author field matches the query name
  def filter_by_author(results, author_query)
    # Extract meaningful name parts (strip initials' dots, ignore short fragments)
    query_parts = author_query.downcase.tr(".", "").split(/\s+/).select { |p| p.length >= 2 }
    return results if query_parts.empty?

    # The last name is the strongest signal
    last_name = query_parts.last

    results.select do |book|
      next false unless book[:author]
      author_lower = book[:author].downcase
      author_lower.include?(last_name)
    end
  end
end
