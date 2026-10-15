# frozen_string_literal: true

# The server_context that McpTools::Server gives a tool. A token has every
# scope unless an example passes fewer.
module McpToolHelpers
  def mcp_context(user, scopes: McpTools::Scopes::NAMES, **rest)
    { user: user, scopes: scopes, **rest }
  end
end

RSpec.configure do |config|
  config.include McpToolHelpers
end
