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
    # server/discover, never to a tool call, a prompt, or a completion.
    #
    # Scope: those results are the same for every token. Every tool and
    # prompt is listed to every token, their descriptions are fixed in code,
    # and the only resources are the static app templates
    # (McpTools.app_resources). So a cache that a client shares between
    # students cannot leak one student's data, and the scope is public.
    #
    # TTL: the results change on a deploy (a new tool, a new week grid
    # template). The server is stateless, so it cannot send list_changed to
    # tell a client to read them again. A short TTL keeps a client at most
    # 5 minutes behind a deploy, and still saves the reads within one chat.
    #
    # A client on an older protocol version gets the two fields in the list
    # results too. JSON-RPC clients ignore result fields they do not know.
    # Before you add a resource or a list that changes for each student, set
    # the scope to private or give that result its own hints.
    CACHE_TTL_MS = 5 * 60 * 1000
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
        configuration:  configuration(user: user, application: application, request: request),
        request_state_security: request_state_security(user),
        # A write tool returns input_required only on the 2026-07-28 wire
        # (McpTools::Confirmation). On an older wire the shim sends a
        # server-to-client request, which a stateless JSON response cannot
        # carry, so it stays off.
        input_required_legacy_shim: false
      ).tap do |server|
        server.completion_handler { |params| Completions.call(params) }
      end
    end

    # The confirmation of a write tool (McpTools::Confirmation) sends a request
    # state to the client, and the client sends it back on the retry. The SDK
    # encrypts it with AES-256-GCM and binds it to the tool, a digest of the
    # arguments, an expiry, and the audience. The audience is the user, so the
    # state of one student cannot complete the call of another.
    #
    # Both deploy slots must read a state that the other slot sealed, so the
    # key comes from secret_key_base. Change the salt to make every open
    # state invalid.
    REQUEST_STATE_SALT = "mcp request state v1"
    REQUEST_STATE_TTL  = 10.minutes.to_i

    def self.request_state_security(user)
      MCP::Server::RequestStateSecurity.new(key: request_state_key, ttl: REQUEST_STATE_TTL, audience: "user:#{user.id}")
    end

    def self.request_state_key
      Rails.application.key_generator.generate_key(REQUEST_STATE_SALT, MCP::Server::RequestStateSecurity::KEY_BYTES)
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

    def self.configuration(user:, application:, request: nil)
      MCP::Configuration.new(
        # The SDK sends the client a generic error and calls this with the
        # cause. It handles the error, so the report says handled.
        exception_reporter: lambda do |exception, _context|
          next if client_error?(exception)

          cause = exception.respond_to?(:original_error) && exception.original_error || exception
          Rails.error.report(cause, handled: true, context: { user_id: user.id, oauth_application_id: application&.id })
        end,
        around_request: lambda do |data, &handler|
          result = handler.call
          count_tool_call(data, request, status: tool_call_status(data, result))
          result
        rescue StandardError
          count_tool_call(data, request, status: "error")
          raise
        end
      )
    end

    # ok, error, input_required (the question of McpTools::Confirmation), or
    # declined or cancelled (the student did not confirm).
    def self.tool_call_status(data, result)
      return "error" if data[:error].present?
      return "input_required" if data[:input_required]
      return "ok" unless result.is_a?(Hash)
      return "error" if result[:isError]

      reason = result.dig(:structuredContent, :not_changed, :reason) if result[:structuredContent].is_a?(Hash)
      %w[declined cancelled].include?(reason) ? reason : "ok"
    end

    # Invalid params with no cause: a bad request from the client, such as
    # prompt arguments that are not an object or an unknown prompt. The client
    # gets -32602 with the reason. It is not a fault, so it is not reported,
    # the same as a 4xx from the API.
    #
    # A request state that is changed, expired, or for another call or user
    # (request_state_security) is a client error too. The client gets -32602
    # "Invalid or expired requestState" and calls the tool again without it.
    def self.client_error?(exception)
      cause = exception.respond_to?(:original_error) ? exception.original_error : exception
      return true if cause.is_a?(MCP::Server::RequestStateSecurity::InvalidStateError)

      exception.is_a?(MCP::Server::RequestHandlerError) && exception.original_error.nil? &&
        (exception.error_code == ::JsonRpcHandler::ErrorCode::INVALID_PARAMS || exception.error_type == :invalid_params)
    end

    # Unknown tool names go in one bucket, so a client cannot add label values.
    # The SDK names the tool only when it reaches the tool. A retry with a bad
    # request state fails before that, so the name then comes from the body.
    def self.count_tool_call(data, request, status:)
      return unless data[:method] == "tools/call"

      name = data[:tool_name] || requested_tool_name(request)
      tool = McpTools.names.include?(name) ? name : "unknown"
      Yabeda.calendar.mcp_tool_calls_total.increment({ tool: tool, status: status })
    end

    def self.requested_tool_name(request)
      params = request&.request_parameters&.dig("params")
      params["name"] if params.is_a?(Hash)
    rescue ActionDispatch::Http::Parameters::ParseError
      nil
    end

    def self.icon_url
      "#{Rails.application.routes.url_helpers.root_url(**url_options).chomp('/')}/icon.png"
    end

    def self.url_options
      Rails.application.config.action_controller.default_url_options || {}
    end
  end
end
