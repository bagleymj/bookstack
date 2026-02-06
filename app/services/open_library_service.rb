require "net/http"
require "json"

class OpenLibraryService
  BASE_URL = "https://openlibrary.org"
  COVER_URL = "https://covers.openlibrary.org"
  TIMEOUT = 5 # seconds

  class ApiError < StandardError; end

  # Search for books by title/author query
  # Returns array of book hashes with normalized fields
  def search(query, limit: 10)
    return [] if query.blank?

    params = {
      q: query,
      limit: limit,
      fields: "title,author_name,first_publish_year,number_of_pages_median,isbn,cover_i,key"
    }

    response = get("/search.json", params)
    docs = response["docs"] || []

    docs.map { |doc| normalize_search_result(doc) }.compact
  rescue ApiError, Net::TimeoutError, JSON::ParserError => e
    Rails.logger.error("OpenLibrary search error: #{e.message}")
    []
  end

  # Fetch a single book by ISBN
  # Returns normalized book hash or nil
  def fetch_by_isbn(isbn)
    return nil if isbn.blank?

    # Clean ISBN (remove dashes, spaces)
    clean_isbn = isbn.to_s.gsub(/[-\s]/, "")

    response = get("/isbn/#{clean_isbn}.json")
    normalize_isbn_result(response, clean_isbn)
  rescue ApiError, Net::TimeoutError, JSON::ParserError => e
    Rails.logger.error("OpenLibrary ISBN lookup error: #{e.message}")
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

  def normalize_search_result(doc)
    return nil unless doc["title"].present?

    cover_id = doc["cover_i"]
    isbn = doc["isbn"]&.first

    {
      title: doc["title"],
      author: doc["author_name"]&.first,
      year: doc["first_publish_year"],
      pages: doc["number_of_pages_median"],
      isbn: isbn,
      cover_url: cover_id ? cover_url(cover_id, :medium) : nil,
      cover_url_small: cover_id ? cover_url(cover_id, :small) : nil,
      open_library_key: doc["key"]
    }
  end

  def normalize_isbn_result(doc, isbn)
    return nil unless doc["title"].present?

    # ISBN endpoint returns edition data, need to extract what we can
    covers = doc["covers"]
    cover_id = covers&.first

    {
      title: doc["title"],
      author: nil, # ISBN endpoint doesn't include author directly
      pages: doc["number_of_pages"],
      isbn: isbn,
      cover_url: cover_id ? cover_url(cover_id, :medium) : nil,
      cover_url_small: cover_id ? cover_url(cover_id, :small) : nil,
      open_library_key: doc["key"]
    }
  end

  def cover_url(cover_id, size = :medium)
    size_code = case size
    when :small then "S"
    when :medium then "M"
    when :large then "L"
    else "M"
    end

    "#{COVER_URL}/b/id/#{cover_id}-#{size_code}.jpg"
  end
end
