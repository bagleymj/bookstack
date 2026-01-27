module ApplicationHelper
  def status_badge_class(status)
    case status.to_s
    when "unread"
      "bg-gray-100 text-gray-800"
    when "reading"
      "bg-blue-100 text-blue-800"
    when "completed"
      "bg-green-100 text-green-800"
    when "abandoned"
      "bg-red-100 text-red-800"
    when "active"
      "bg-indigo-100 text-indigo-800"
    when "pending"
      "bg-yellow-100 text-yellow-800"
    when "missed"
      "bg-red-100 text-red-800"
    when "adjusted"
      "bg-orange-100 text-orange-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def difficulty_badge_class(difficulty)
    case difficulty.to_s
    when "easy"
      "bg-green-100 text-green-800"
    when "below_average"
      "bg-lime-100 text-lime-800"
    when "average"
      "bg-yellow-100 text-yellow-800"
    when "challenging"
      "bg-orange-100 text-orange-800"
    when "dense"
      "bg-red-100 text-red-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end
end
