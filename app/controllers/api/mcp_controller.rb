# frozen_string_literal: true

module Api
  # The MCP server (docs/mcp.md), over Streamable HTTP in stateless mode.
  #
  # It takes an OAuth access token from the Doorkeeper server
  # (config/routes/oauth.rb), not an extension JWT. A request with no valid
  # token gets 401 and a WWW-Authenticate header that points to the protected
  # resource metadata (RFC 9728), which is how an MCP client finds the sign-in.
  class McpController < BaseController
    SCOPE = "read"

    before_action :authenticate_oauth_token!

    # POST /api/mcp
    def create
      server    = McpTools::Server.build(user: current_user, application: @access_token.application, request: request)
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless:                  true,
        enable_json_response:       true,
        serve_subscriptions_listen: false,
        # The bearer token, not a cookie, signs the request in, so a page on
        # another origin gains nothing from a rebound host name. Rails checks
        # the Host header (config.hosts) before this runs.
        dns_rebinding_protection:   false
      )

      status, headers, body = transport.handle_request(request)
      headers.each { |name, value| response.headers[name] = value }
      render body: read_body(body), status: status, content_type: headers["Content-Type"] || "application/json"
    end

    # GET and DELETE /api/mcp. A stateless server has no event stream and no
    # session to end.
    def method_not_allowed
      response.headers["Allow"] = "POST"
      render_error "Use POST", status: :method_not_allowed
    end

    private

    def authenticate_oauth_token!
      @access_token = Doorkeeper::OAuth::Token.authenticate(request, *Doorkeeper.config.access_token_methods)

      if @access_token.nil? && request.authorization.blank?
        challenge
        render_error "Authentication required", status: :unauthorized, code: "AUTH_MISSING"
      elsif @access_token.nil? || !@access_token.accessible?
        challenge(error: "invalid_token", description: "The access token expired or was revoked")
        render_error "Authentication required", status: :unauthorized, code: "AUTH_INVALID"
      elsif !@access_token.includes_scope?(SCOPE)
        challenge(error: "insufficient_scope", description: "The token needs the #{SCOPE} scope")
        render_error "The token needs the #{SCOPE} scope", status: :forbidden, code: "INSUFFICIENT_SCOPE"
      else
        # A foreign key ties the token to the user, and deleting a user deletes
        # the tokens, so the user is always there.
        @current_user = User.find(@access_token.resource_owner_id)
      end
    end

    # RFC 6750 section 3 and RFC 9728 section 5.1.
    def challenge(error: nil, description: nil)
      metadata = Oauth::Metadata.new(host: request.host, port: request.port, protocol: request.protocol)
      parts = [ %(resource_metadata="#{metadata.resource_metadata_url}"), %(scope="#{SCOPE}") ]
      parts << %(error="#{error}") if error
      parts << %(error_description="#{description}") if description
      response.headers["WWW-Authenticate"] = "Bearer #{parts.join(', ')}"
    end

    # The transport answers with a list of strings, or with a stream body
    # when it sends server events. Stateless JSON mode should not stream, but
    # a stream body is read to the end so no answer is lost.
    def read_body(body)
      return body.join if body.respond_to?(:join)

      buffer = StringIO.new
      body.call(buffer)
      buffer.string
    end
  end
end
