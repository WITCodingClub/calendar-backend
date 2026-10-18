# frozen_string_literal: true

module McpTools
  # Counts an MCP semantic search against the catalog/semantic budget, the
  # same budget as REST and GraphQL. The request carries the user's token, so
  # Rack::Attack counts it against that user, not the shared address of the
  # client. Without a request (a tool called outside a request) nothing counts.
  class SemanticBudget
    def initialize(request)
      @request = request
    end

    # Counts one search. Raises ToolError when the budget is used up.
    def spend!
      return if @request.nil?
      return unless Rack::Attack.semantic_search_throttled?(@request.env)

      raise ToolError, "Too many semantic searches. Wait a minute, or search without semantic."
    end
  end
end
