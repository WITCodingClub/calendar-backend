# frozen_string_literal: true

module Analyzers
  # Limits the semantic searches in one GraphQL query.
  #
  # A semantic search embeds its words, and new words cost an API call. The
  # call runs inside the request. Aliases let one query ask for many searches,
  # and each costs only a few points of complexity, so one request could make
  # hundreds of calls and hold a Puma thread for all of them.
  #
  # The analyzer runs before any field resolves. It allows one search for each
  # query, and counts that search against the same Rack::Attack budget as a
  # REST request with semantic=true.
  class SemanticSearchLimit < GraphQL::Analysis::Analyzer
    MAX_PER_QUERY = 1

    def initialize(query)
      super
      @searches = 0
    end

    def on_enter_field(node, _parent, visitor)
      return if visitor.skipping? || visitor.field_definition.nil?

      arguments = visitor.query.arguments_for(node, visitor.field_definition)
      return if arguments.is_a?(GraphQL::ExecutionError)

      @searches += 1 if semantic_search?(arguments) || semantic_search?(arguments[:filter])
    end

    def result
      return if @searches.zero?

      if @searches > MAX_PER_QUERY
        GraphQL::AnalysisError.new(
          "A query can run at most #{MAX_PER_QUERY} semantic search. It asks for #{@searches}.",
          extensions: { "code" => "TOO_MANY_SEMANTIC_SEARCHES" }
        )
      elsif throttled?
        GraphQL::AnalysisError.new(
          "Rate limit exceeded for semantic search. Please try again later.",
          extensions: { "code" => "RATE_LIMITED" }
        )
      end
    end

    private

    # Without words there is nothing to embed, so semantic: true alone is free.
    def semantic_search?(arguments)
      return false unless arguments.respond_to?(:key?)

      arguments.key?(:semantic) && arguments[:semantic] && arguments[:q].present?
    end

    def throttled?
      request = query.context[:request]
      return false unless request

      Rack::Attack.semantic_search_throttled?(request.env)
    end
  end
end
