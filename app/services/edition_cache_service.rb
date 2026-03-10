class EditionCacheService
  # Overlay local Edition data onto Google Books editions.
  # For editions with ISBNs matching local records, merge in:
  # - recommended page range
  # - local page count (if available)
  # - has_local_data flag
  def overlay_local_data(editions)
    isbns = editions.filter_map { |e| e[:isbn] }.uniq
    return editions if isbns.empty?

    local_editions = Edition.where(isbn: isbns).index_by(&:isbn)

    editions.map do |edition|
      local = local_editions[edition[:isbn]]
      if local
        edition.merge(
          recommended_first_page: local.recommended_first_page,
          recommended_last_page: local.recommended_last_page,
          has_local_data: true
        )
      else
        edition.merge(has_local_data: false)
      end
    end
  end

  # Record a page range vote for an edition.
  # Find-or-creates the Edition by ISBN, then upserts the user's vote.
  def record_page_range(user:, isbn:, first_page:, last_page:, metadata: {})
    return if isbn.blank? || first_page.blank? || last_page.blank?

    edition = Edition.find_or_initialize_by(isbn: isbn)
    edition.assign_attributes(metadata.slice(:title, :author, :publisher, :published_year, :page_count, :cover_image_url, :format, :google_books_id))
    edition.save!

    vote = PageRangeVote.find_or_initialize_by(edition: edition, user: user)
    vote.assign_attributes(first_page: first_page, last_page: last_page)
    vote.save!
  end
end
