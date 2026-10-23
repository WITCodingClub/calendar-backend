# frozen_string_literal: true

module McpTools
  # Builds the MCP server for one request. The server is stateless: each POST
  # carries the bearer token and gets a new server for its user.
  class Server
    NAME = "wit-calendar"

    INSTRUCTIONS = <<~TEXT.squish
      Access to the Wentworth Institute of Technology course catalog and to the signed-in
      student's schedule on WIT Calendar. Call list_terms first to get term uids. Times are in
      the America/New_York time zone. Each tool needs a permission that the student gives when
      they connect. Tools that change data need a permission that is off by default. When a
      tool answers that a permission is missing, tell the student how to add it and do not
      retry. Before you change a setting, say what you will change. WIT Calendar is not an
      official Wentworth service. It copies course data from official Wentworth sources on a
      schedule, and the advisory in a course result says when it last did. When you help a
      student plan courses, tell them to confirm the plan with their program director and
      their academic advisor.
    TEXT

    DESCRIPTION = "Wentworth course catalog and your WIT Calendar schedule and settings."

    # SEP-2549 cache hints. The SDK adds them to the list and read results
    # (tools/list, prompts/list, resources/list, resources/read) and to
    # server/discover, never to a tool call or a prompt. Those results are the
    # same for every token: every tool and prompt is listed to every token,
    # their descriptions are fixed in code, and the only resources are the
    # static app templates (McpTools.app_resources).
    # So a cache that a client shares between students cannot leak one
    # student's data, and the scope is public. The lists change only on a
    # deploy, so a client can keep them for one hour.
    #
    # A client on an older protocol version gets the two fields in the list
    # results too. JSON-RPC clients ignore result fields they do not know.
    # Before you add a resource or a list that changes for each student, set
    # the scope to private or give that result its own hints.
    CACHE_TTL_MS = 60 * 60 * 1000
    CACHE_SCOPE  = "public"

    # scopes: the scope names of the token, expanded (McpTools::Scopes.expand).
    def self.build(user:, application:, scopes:, request: nil)
      MCP::Server.new(
        name:           NAME,
        title:          "WIT Calendar",
        description:    DESCRIPTION,
        # Clients show this icon next to the connector, where they support
        # serverInfo icons (MCP 2025-11-25). public/icon.png is 180x180.
        icons:          [ { src: icon_url, mime_type: "image/png", sizes: [ "180x180" ] } ],
        version:        VersionService.current_version.to_s,
        website_url:    Rails.application.routes.url_helpers.mcp_docs_url(**url_options),
        instructions:   INSTRUCTIONS,
        tools:          McpTools.all,
        resources:      McpTools.app_resources,
        prompts:        McpTools::Prompts.all,
        capabilities:   capabilities,
        ttl_ms:         CACHE_TTL_MS,
        cache_scope:    CACHE_SCOPE,
        server_context: { user: user, scopes: scopes, request: request },
        configuration:  configuration(user: user, application: application)
      ).tap do |server|
        server.completion_handler { |params| Completions.call(params) }
      end
    end

    # The SDK defaults, plus completions for the prompt arguments
    # (McpTools::Completions) and the MCP Apps extension (docs/mcp.md, "Apps").
    # The server is stateless, so it cannot see what the client declared at
    # initialize. It always links tools to their app; a client without the
    # extension ignores the link and reads the normal result.
    def self.capabilities
      MCP::Server::Capabilities.new(
        tools:       { listChanged: true },
        prompts:     { listChanged: true },
        resources:   { listChanged: true },
        logging:     {},
        completions: {},
        extensions:  MCP::Apps.capability
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

    def self.icon_url
      "#{Rails.application.routes.url_helpers.root_url(**url_options).chomp('/')}/icon.png"
    end

    def self.url_options
      Rails.application.config.action_controller.default_url_options || {}
    end
  end
end
