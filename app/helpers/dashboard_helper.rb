module DashboardHelper
  def stat_card_definitions
    [
      { key: "reading_speed",        label: "Est. Reading Speed",                            default: true },
      { key: "total_sessions",       label: "Total Sessions",                           default: true },
      { key: "pages_read",           label: "Pages Read",                               default: true },
      { key: "time_reading",         label: "Time Reading",                             default: true },
      { key: "yearly_scheduled",     label: "#{Date.current.year} Books Scheduled",     default: true },
      { key: "yearly_completed",     label: "#{Date.current.year} Books Completed",     default: true },
      { key: "pages_today",          label: "Pages Today",                              default: false },
      { key: "time_today",           label: "Time Today",                               default: false },
      { key: "pages_this_week",      label: "Pages This Week",                          default: false },
      { key: "time_this_week",       label: "Time This Week",                           default: false },
      { key: "pages_per_hour",       label: "Pages/Hour",                               default: false },
      { key: "books_completed",      label: "Books Completed",                          default: false },
      { key: "avg_pages_session",    label: "Avg Pages/Session",                        default: false },
      { key: "avg_session_duration", label: "Avg Session",                              default: false },
      { key: "reading_streak",       label: "Reading Streak",                           default: false }
    ]
  end

  def stat_card_defaults
    stat_card_definitions.each_with_object({}) { |card, hash| hash[card[:key]] = card[:default] }
  end

  def render_stat_card(key:, label:, value:)
    content_tag(:div,
      class: "rounded-lg bg-white p-4 shadow",
      data: { stat_cards_target: "card", stat_key: key }
    ) do
      content_tag(:dt, label, class: "text-sm font-medium text-gray-500") +
      content_tag(:dd, value, class: "mt-1 text-2xl font-semibold text-gray-900")
    end
  end

  def format_duration(seconds)
    return "0 min" if seconds.nil? || seconds.zero?
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    if hours.zero?
      "#{minutes} min"
    else
      "#{hours}h #{minutes}m"
    end
  end
end
