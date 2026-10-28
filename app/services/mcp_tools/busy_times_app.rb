# frozen_string_literal: true

module McpTools
  # The busy times MCP App: one row for each day, with a bar for each busy
  # time. my_busy_times and friend_busy_times show their result in it.
  class BusyTimesApp < AppResource
    uri "ui://wit-calendar/busy-times"
    resource_name "busy_times"
    title "Busy times"
    description "The busy times of each day in a date range."
    mime_type MCP::Apps::RESOURCE_MIME_TYPE
    template "busy_times.html"
  end
end
