module GoodreadsHelper
  def shelf_badge_class(shelf)
    case shelf
    when "to-read"
      "bg-gray-100 text-gray-800"
    when "currently-reading"
      "bg-blue-100 text-blue-800"
    when "read"
      "bg-green-100 text-green-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end
end
