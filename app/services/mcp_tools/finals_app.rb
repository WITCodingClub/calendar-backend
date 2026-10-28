# frozen_string_literal: true

module McpTools
  # The final exams MCP App: the exams of my_finals, grouped by day.
  class FinalsApp < AppResource
    uri "ui://wit-calendar/finals"
    resource_name "finals"
    title "Final exams"
    description "Final exams grouped by day, with the time and the room."
    mime_type MCP::Apps::RESOURCE_MIME_TYPE
    template "finals.html"
  end
end
