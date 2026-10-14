# frozen_string_literal: true

module McpTools
  # Builds the MCP server for one request. The server is stateless: each POST
  # carries the bearer token and gets a new server for its user.
  class Server
    NAME = "wit-calendar"

    INSTRUCTIONS = <<~TEXT.squish
      Read-only access to the Wentworth Institute of Technology course catalog and to the
      signed-in student's schedule on WIT Calendar. Call list_terms first to get term uids.
      Times are in the America/New_York time zone.
    TEXT

    def self.build(user:, application:, request: nil)
      MCP::Server.new(
        name:           NAME,
        title:          "WIT Calendar",
        version:        VersionService.current_version.to_s,
        website_url:    Rails.application.routes.url_helpers.mcp_docs_url(**url_options),
        instructions:   INSTRUCTIONS,
        tools:          McpTools.all,
        server_context: { user: user, request: request },
        configuration:  configuration(user: user, application: application)
      )
    end

    def self.configuration(user:, application:)
      MCP::Configuration.new(
        # The SDK sends the client a generic error and calls this with the
        # cause. It handles the error, so the report says handled.
        exception_reporter: lambda do |exception, _context|
          cause = exception.respond_to?(:original_error) && exception.original_error || exception
          Rails.error.report(cause, handled: true, context: { user_id: user.id, oauth_application_id: application&.id })
        end,
        around_request: lambda do |data, &handler|
          result = handler.call
          count_tool_call(data, failed: data[:error].present? || (result.is_a?(Hash) && result[:isError]))
          result
        rescue StandardError
          count_tool_call(data, failed: true)
          raise
        end
      )
    end

    # Unknown tool names go in one bucket, so a client cannot add label values.
    def self.count_tool_call(data, failed:)
      return unless data[:method] == "tools/call"

      tool = McpTools.names.include?(data[:tool_name]) ? data[:tool_name] : "unknown"
      Yabeda.calendar.mcp_tool_calls_total.increment({ tool: tool, status: failed ? "error" : "ok" })
    end

    def self.url_options
      Rails.application.config.action_controller.default_url_options || {}
    end
  end
end
