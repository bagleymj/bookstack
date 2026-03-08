require "net/http"
require "json"

class OpenLibraryService
  BASE_URL = "https://openlibrary.org"
  COVERS_URL = "https://covers.openlibrary.org/b/id"
  TIMEOUT = 8 # seconds — Open Library can be slow

  class ApiError < StandardError; end

  # Search for works (step 1).
  # Returns an array of work hashes sorted by relevance/quality.
  def search_works(query, limit: 8)
    return [] if query.blank?

    params = {
      q: query,
      limit: [limit * 3, 24].max, # overfetch for ranking
      fields: "key,title,author_name,first_publish_year,edition_count,cover_i"
    }

    data = get("/search.json", params)
    docs = data["docs"] || []

    docs
      .select { |doc| doc["edition_count"].to_i > 0 }
      .map { |doc| normalize_work(doc) }
      .compact
      .sort_by { |w| -work_score(w) }
      .first(limit)
  rescue ApiError, Net::TimeoutError, JSON::ParserError, Errno::ECONNREFUSED => e
    Rails.logger.error("OpenLibrary search error: #{e.message}")
    []
  end

  # Fetch editions for a work (step 2).
  # work_key: e.g. "/works/OL55847W" or just "OL55847W"
  def fetch_editions(work_key, limit: 25)
    return [] if work_key.blank?

    work_id = work_key.split("/").last # handle both "/works/OL55847W" and "OL55847W"
    data = get("/works/#{work_id}/editions.json", { limit: limit })
    entries = data["entries"] || []

    entries
      .map { |entry| normalize_edition(entry) }
      .compact
      .sort_by { |e| -edition_score(e) }
  rescue ApiError, Net::TimeoutError, JSON::ParserError, Errno::ECONNREFUSED => e
    Rails.logger.error("OpenLibrary editions error: #{e.message}")
    []
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
    request["User-Agent"] = "BookStack/1.0 (Reading Goal Tracker; mailto:contact@bookstack.app)"
    request["Accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "HTTP #{response.code}: #{response.message}"
    end

    JSON.parse(response.body)
  end

  def normalize_work(doc)
    {
      key: doc["key"],
      title: doc["title"],
      author: Array(doc["author_name"]).first,
      first_publish_year: doc["first_publish_year"],
      edition_count: doc["edition_count"].to_i,
      cover_url: cover_url(doc["cover_i"])
    }
  rescue StandardError => e
    Rails.logger.warn("OpenLibrary: failed to normalize work: #{e.message}")
    nil
  end

  def normalize_edition(entry)
    pages = entry["number_of_pages"]
    isbn_13 = Array(entry["isbn_13"]).first
    isbn_10 = Array(entry["isbn_10"]).first
    isbn = isbn_13 || isbn_10

    # Filter out editions missing both pages AND isbn
    return nil if pages.nil? && isbn.nil?

    cover_id = Array(entry["covers"]).first

    {
      key: entry["key"],
      title: entry["title"],
      publisher: Array(entry["publishers"]).first,
      year: extract_year(entry["publish_date"]),
      pages: pages,
      isbn: isbn,
      format: entry["physical_format"]&.capitalize,
      cover_url: cover_url(cover_id)
    }
  rescue StandardError => e
    Rails.logger.warn("OpenLibrary: failed to normalize edition: #{e.message}")
    nil
  end

  def cover_url(cover_id)
    return nil unless cover_id
    "#{COVERS_URL}/#{cover_id}-M.jpg"
  end

  def extract_year(publish_date)
    return nil if publish_date.blank?
    # publish_date can be "2006", "March 2006", "Mar 15, 2006", etc.
    match = publish_date.match(/(\d{4})/)
    match ? match[1] : nil
  end

  def work_score(work)
    score = 0.0
    score += 10 if work[:cover_url]
    score += 5  if work[:first_publish_year]
    score += 5  if work[:author]
    # More editions = more well-known
    score += [work[:edition_count], 100].min * 0.2
    score
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
