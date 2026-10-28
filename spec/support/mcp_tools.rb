# frozen_string_literal: true

# The mcp gem defines MCP::ServerContext only when it loads MCP::Server. A
# spec that runs before anything loads the server needs it here.
require "mcp/server"

# The server_context that McpTools::Server gives a tool. A token has every
# scope unless an example passes fewer.
module McpToolHelpers
  def mcp_context(user, scopes: McpTools::Scopes::NAMES, **rest)
    { user: user, scopes: scopes, **rest }
  end

  # The context of a call on the 2026-07-28 wire, where each request names
  # the client capabilities. By default the client declares form
  # elicitation, so a write tool asks the student to confirm. A retry passes
  # the answer and the request state, which the SDK gives the tool unsealed.
  def mcp_modern_context(user, capabilities: { elicitation: { form: {} } }, input_responses: nil, request_state: nil, **rest)
    MCP::ServerContext.new(
      mcp_context(user, **rest),
      progress:            nil,
      notification_target: nil,
      envelope:            MCP::RequestEnvelope.new(protocol_version: "2026-07-28", client_capabilities: capabilities),
      input_responses:     input_responses,
      request_state:       request_state
    )
  end

  # An answer to the confirmation (McpTools::Confirmation::KEY).
  def mcp_confirmation(action, confirm: true)
    answer = { action: action }
    answer[:content] = { confirm: confirm } if action == "accept"
    { McpTools::Confirmation::KEY => answer }
  end
end

RSpec.configure do |config|
  config.include McpToolHelpers
end
