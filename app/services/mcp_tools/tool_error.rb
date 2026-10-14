# frozen_string_literal: true

module McpTools
  # A tool argument the tool cannot use. The message goes back to the client.
  class ToolError < StandardError; end
end
