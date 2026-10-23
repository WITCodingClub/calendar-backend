# frozen_string_literal: true

module McpTools
  # Asks the student to confirm a change before a write tool makes it, with
  # MCP elicitation (docs/mcp.md, "Confirmation"). The client shows the
  # message and a "confirm" box, and the student accepts or declines.
  #
  # The server is stateless, so it uses the multi round-trip form of MCP
  # 2026-07-28 (SEP-2322): the first call returns an input_required result,
  # and the client calls the tool again with the answer and the request
  # state. The tool runs again from the start, so every check runs again.
  #
  # A client that did not declare form elicitation on the 2026-07-28 wire
  # cannot answer. For it, #call returns :accept, so the tool makes the
  # change as it did before this step.
  #
  # The SDK seals the request state (McpTools::Server.request_state_security):
  # the client cannot read or change it, and it is bound to the tool, the
  # arguments, and the user. The state holds a digest of the message, so a
  # retry applies the change only if the student saw the same message.
  class Confirmation
    KEY = "confirm"

    REQUESTED_SCHEMA = {
      type:       "object",
      properties: {
        confirm: {
          type:        "boolean",
          title:       "Make this change",
          description: "Check the box to make the change. Leave it clear to change nothing.",
          default:     false
        }
      },
      required:   [ "confirm" ]
    }.freeze

    def initialize(server_context, user:)
      @server_context = server_context
      @user           = user
    end

    # Returns :accept, :decline, :cancel, or an MCP::Server::InputRequiredResult
    # that the tool returns to ask the student.
    def call(message)
      question = input_required(message)
      return :accept unless supported?(question)

      state = read_state
      return question unless state && state["u"] == @user.id && state["d"] == digest(message)

      outcome(@server_context.input_response(KEY))
    end

    private

    # Only the 2026-07-28 wire carries the client capabilities in each
    # request, and only it can send an input_required result. On an older
    # wire the SDK would send a server-to-client request, which a stateless
    # JSON response cannot carry.
    def supported?(question)
      return false unless @server_context.respond_to?(:modern?) && @server_context.modern?

      question.missing_client_capabilities(@server_context.client_capabilities || {}).empty?
    end

    def input_required(message)
      MCP::Server::InputRequiredResult.new(
        input_requests: {
          KEY => {
            method: MCP::Methods::ELICITATION_CREATE,
            params: { mode: "form", message: message, requestedSchema: REQUESTED_SCHEMA }
          }
        },
        request_state: JSON.generate(u: @user.id, d: digest(message))
      )
    end

    # The SDK gives the state in plain text after it checks the seal.
    def read_state
      state = @server_context.request_state
      return if state.nil?

      parsed = JSON.parse(state)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def outcome(response)
      response = response.to_h.deep_stringify_keys if response.respond_to?(:to_h)

      case response.is_a?(Hash) && response["action"]
      when "accept" then response.dig("content", "confirm") == true ? :accept : :decline
      when "decline" then :decline
      else :cancel
      end
    end

    def digest(message) = OpenSSL::Digest::SHA256.hexdigest(message)
  end
end
