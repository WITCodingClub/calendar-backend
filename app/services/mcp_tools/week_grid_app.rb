# frozen_string_literal: true

module McpTools
  # The week grid MCP App: a week grid of class meetings that marks time
  # conflicts. check_schedule and my_courses show their result in it.
  class WeekGridApp < AppResource
    uri "ui://wit-calendar/week-grid"
    resource_name "week_grid"
    title "Week grid"
    description "A week grid of class meetings. It marks time conflicts."
    mime_type MCP::Apps::RESOURCE_MIME_TYPE
    template "week_grid.html"
  end
end
