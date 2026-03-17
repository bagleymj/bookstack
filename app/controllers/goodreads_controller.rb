class GoodreadsController < ApplicationController
  before_action :authenticate_user!

  # GET /goodreads — landing page with import/export options
  def show
  end

  # POST /goodreads/preview — parse CSV and show preview
  def preview
    unless params[:file].present?
      redirect_to goodreads_path, alert: "Please select a CSV file."
      return
    end

    csv_content = params[:file].read.force_encoding("UTF-8")
    service = GoodreadsImportService.new(current_user)
    @entries = service.parse(csv_content)

    if @entries.empty?
      redirect_to goodreads_path, alert: "No books found in the CSV file."
      return
    end

    # Group by exclusive shelf for filtering
    @shelves = @entries.map { |e| e[:exclusive_shelf] }.compact.uniq.sort
    @existing_isbns = current_user.books.where.not(isbn: [nil, ""]).pluck(:isbn).to_set
  end

  # POST /goodreads/import — actually create the books
  def import
    raw_books = params[:books]
    entries = extract_book_entries(raw_books)

    if entries.empty?
      redirect_to goodreads_path, alert: "No books selected for import."
      return
    end

    service = GoodreadsImportService.new(current_user)
    @result = service.import(entries)
  end

  def extract_book_entries(raw_books)
    return [] if raw_books.blank?

    raw_books.select { |bp| bp.respond_to?(:permit) }.map do |bp|
      bp.permit(:title, :author, :isbn, :last_page, :status).to_h.symbolize_keys
    end
  end

  # GET /goodreads/export — download BookStack library as Goodreads CSV
  def export
    books = current_user.books.order(:title)

    if params[:status].present?
      books = books.where(status: params[:status])
    end

    csv = GoodreadsExportService.new(current_user).generate(books)

    send_data csv,
      filename: "bookstack_export_#{Date.current.iso8601}.csv",
      type: "text/csv; charset=utf-8",
      disposition: "attachment"
  end
end
