require "net/http"
require "json"

class GoogleBooksService
  BASE_URL = "https://www.googleapis.com/books/v1/volumes"
  TIMEOUT = 8

  class ApiError < StandardError; end

  # Search for works (step 1).
  # Groups Google Books results by normalized title + first author to
  # synthesize "works". Returns array of work hashes preserving relevance.
  def search_works(query, limit: 8, search_type: nil)
    return [] if query.blank?

    qualified = build_qualified_query(query, search_type)
    params = {
      q: qualified,
      maxResults: 40,
      printType: "books",
      orderBy: "relevance"
    }

    data = get(params)
    items = data["items"] || []

    group_into_works(items)
      .first(limit)
  rescue ApiError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, Errno::ECONNREFUSED => e
    Rails.logger.error("GoogleBooks search error: #{e.message}")
    []
  end

  # Fetch editions for a work (step 2).
  # work_key is "title|||author" — searches Google Books with intitle+inauthor.
  def fetch_editions(work_key)
    return [] if work_key.blank?

    title, author = work_key.split("|||", 2)
    return [] if title.blank?

    parts = ["intitle:#{title}"]
    parts << "inauthor:#{author}" if author.present?
    query = parts.join("+")

    all_items = []
    start_index = 0
    batch_size = 40

    # Paginate up to 3 pages (120 results max)
    3.times do
      params = {
        q: query,
        maxResults: batch_size,
        startIndex: start_index,
        printType: "books"
      }

      data = get(params)
      items = data["items"] || []
      break if items.empty?

      all_items.concat(items)
      break if items.size < batch_size

      start_index += batch_size
    end

    seen_isbns = Set.new
    all_items
      .map { |item| normalize_edition(item) }
      .compact
      .reject { |e| e[:isbn] && !seen_isbns.add?(e[:isbn]) } # deduplicate by ISBN
      .sort_by { |e| -edition_score(e) }
  rescue ApiError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, Errno::ECONNREFUSED => e
    Rails.logger.error("GoogleBooks editions error: #{e.message}")
    []
  end

  private

  def build_qualified_query(query, search_type)
    case search_type&.to_s
    when "title"
      "intitle:#{query}"
    when "author"
      "inauthor:#{query}"
    when "isbn"
      "isbn:#{query}"
    else
      query
    end
  end

  def get(params = {})
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(params) if params.any?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "HTTP #{response.code}: #{response.message}"
    end

    JSON.parse(response.body)
  end

  # Group volumes by normalized title + first author to synthesize "works"
  def group_into_works(items)
    groups = {}
    items.each do |item|
      info = item["volumeInfo"] || {}
      title = info["title"]
      next if title.blank?

      author = Array(info["authors"]).first
      key = normalize_work_key(title, author)

      if groups[key]
        groups[key][:count] += 1
        # Keep the best cover (first one that has it)
        groups[key][:cover_url] ||= extract_cover_url(info)
      else
        groups[key] = {
          key: "#{title}|||#{author}",
          title: title,
          author: author,
          first_publish_year: extract_year(info["publishedDate"]),
          edition_count: 1,
          cover_url: extract_cover_url(info),
          count: 1
        }
      end
    end

    groups.values
      .each { |w| w[:edition_count] = w.delete(:count) }
  end

  def normalize_work_key(title, author)
    normalized_title = title.to_s.downcase.gsub(/[^a-z0-9\s]/, "").squish
    normalized_author = author.to_s.downcase.gsub(/[^a-z0-9\s]/, "").squish
    "#{normalized_title}|||#{normalized_author}"
  end

  def normalize_edition(item)
    info = item["volumeInfo"] || {}
    title = info["title"]
    return nil if title.blank?

    isbn = extract_isbn(info)
    pages = info["pageCount"]

    # Filter out editions missing both pages AND isbn
    return nil if pages.nil? && isbn.nil?

    {
      key: item["id"],
      title: title,
      publisher: info["publisher"],
      year: extract_year(info["publishedDate"]),
      pages: pages,
      isbn: isbn,
      format: info["printType"]&.capitalize,
      cover_url: extract_cover_url(info)
    }
  rescue StandardError => e
    Rails.logger.warn("GoogleBooks: failed to normalize edition: #{e.message}")
    nil
  end

  def extract_isbn(info)
    identifiers = Array(info["industryIdentifiers"])
    isbn_13 = identifiers.find { |id| id["type"] == "ISBN_13" }&.dig("identifier")
    isbn_10 = identifiers.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")
    isbn_13 || isbn_10
  end

  def extract_cover_url(info)
    url = info.dig("imageLinks", "thumbnail")
    return nil unless url
    url.gsub("http://", "https://")
  end

  def extract_year(date_string)
    return nil if date_string.blank?
    match = date_string.match(/(\d{4})/)
    match ? match[1] : nil
  end

  def edition_score(edition)
    score = 0.0
    score += 15 if edition[:pages]
    score += 10 if edition[:isbn]
    score += 8  if edition[:cover_url]
    score += 5  if edition[:publisher]
    score += 3  if edition[:year]
    score += 2  if edition[:format]
    score
  end
end
