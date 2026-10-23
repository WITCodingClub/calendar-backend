# frozen_string_literal: true

module McpTools
  # The week grid MCP App (the MCP Apps extension, SEP-1865). A host that
  # supports the extension reads this resource and shows the HTML in a
  # sandboxed iframe next to the result of a tool that names it
  # (check_schedule, my_courses). The page gets the tool result from the host
  # over postMessage and draws the week. See docs/mcp.md, "Apps".
  #
  # The HTML is self-contained: inline CSS and JavaScript, no network. So the
  # resource declares no CSP domains, and the host applies its strictest CSP.
  class WeekGridApp < MCP::Resource
    URI_VALUE = "ui://wit-calendar/week-grid"
    TEMPLATE  = Rails.root.join("app/views/mcp_apps/week_grid.html")

    uri URI_VALUE
    resource_name "week_grid"
    title "Week grid"
    description "A week grid of class meetings. It marks time conflicts."
    mime_type MCP::Apps::RESOURCE_MIME_TYPE

    # The _meta of a tool that shows its result in the week grid.
    def self.tool_meta = MCP::Apps.tool_meta(resource_uri: URI_VALUE, legacy: true)

    def self.contents
      MCP::Resource::TextContents.new(
        uri:       URI_VALUE,
        mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
        text:      TEMPLATE.read,
        meta:      { ui: { prefersBorder: true } }
      )
    end
  end
end
