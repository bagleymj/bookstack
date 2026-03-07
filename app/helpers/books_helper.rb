module BooksHelper
  def amazon_link(isbn)
    return nil if isbn.blank?

    tag = Rails.application.credentials.dig(:amazon, :affiliate_tag) || "bookstack-20"
    "https://www.amazon.com/s?k=#{ERB::Util.url_encode(isbn)}&tag=#{ERB::Util.url_encode(tag)}"
  end

  def amazon_affiliate_tag
    Rails.application.credentials.dig(:amazon, :affiliate_tag) || "bookstack-20"
  end
end
