require "net/http"
require "json"

class GoogleBooksService
  BASE_URL = "https://www.googleapis.com"
  TIMEOUT = 5 # seconds
  OVERFETCH_LIMIT = 24 # fetch more than needed so we can rank and filter

  JUNK_TITLE_PATTERNS = /\b(study guide|workbook|companion|cliff.?s?\s*notes|spark\s*notes|
    summary\s*(and|&)\s*analysis|book\s*summary|reader.?s?\s*guide|teacher.?s?\s*guide|
    lesson\s*plans?|test\s*prep|exam\s*review|quiz|for\s*dummies)\b/ix

  class ApiError < StandardError; end

  # Search for books.
  # mode: "all" (default), "title", "author", or "isbn"
  def search(query, limit: 8, mode: "all")
    return [] if query.blank?

    search_query = build_query(query, mode)
    api_limit = [OVERFETCH_LIMIT, limit * 3].max

    params = {
      q: search_query,
      maxResults: api_limit,
      printType: "books",
      langRestrict: "en"
    }

    add_api_key(params)

    response = get("/books/v1/volumes", params)
    items = response["items"] || []

    # Score and sort raw items before normalizing
    scored = items.map { |item| [item, quality_score(item)] }
                  .sort_by { |_item, score| -score }

    results = scored.map { |item, _score| normalize(item) }.compact

    if mode == "author"
      results = filter_by_author(results, query)
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

  # Score a raw Google Books API item by quality signals.
  # Higher score = more likely to be a real, popular, purchasable book.
  def quality_score(item)
    info = item["volumeInfo"] || {}
    sale = item["saleInfo"] || {}
    score = 0.0

    # Metadata completeness
    score += 10 if info["pageCount"].to_i > 0
    score += 10 if info["industryIdentifiers"].present?
    score += 5  if info["imageLinks"].present?
    score += 5  if info["publisher"].present?
    score += 3  if info["authors"].present?
    score += 3  if info["description"].present?

    # Community signals — ratings are strong evidence of a real popular book
    ratings_count = info["ratingsCount"].to_i
    if ratings_count > 0
      score += 15
      score += [ratings_count, 50].min * 0.3 # up to +15 more for heavily rated
      score += (info["averageRating"].to_f - 3.0) * 3 # boost well-rated books
    end

    # Commercial availability — for-sale books are real published editions
    score += 10 if sale["saleability"] == "FOR_SALE"
    score += 3  if sale["saleability"] == "FREE"

    # Penalize junk
    title = info["title"].to_s
    score -= 40 if title.match?(JUNK_TITLE_PATTERNS)

    # Penalize very short works (pamphlets, excerpts)
    page_count = info["pageCount"].to_i
    score -= 10 if page_count > 0 && page_count < 50

    score
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

  def build_query(query, mode)
    case mode
    when "title"  then "intitle:#{query}"
    when "author" then "inauthor:#{query}"
    when "isbn"   then "isbn:#{query.gsub(/[-\s]/, "")}"
    else query
    end
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
