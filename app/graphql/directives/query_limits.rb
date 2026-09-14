# frozen_string_literal: true

module Directives
  # No published standard defines a directive for query limits. This one
  # publishes the limits that CatalogSchema enforces, so a client can check a
  # query before it sends it.
  class QueryLimits < GraphQL::Schema::Directive
    graphql_name "queryLimits"
    description "Limits that the server checks before it runs a query. The server rejects a " \
                "query that costs more than maxCost or nests deeper than maxDepth. The cost " \
                "follows the @cost and @listSize directives."

    locations SCHEMA

    argument :max_cost, Integer, required: true,
             description: "The highest cost that the server runs."
    argument :max_depth, Integer, required: true,
             description: "The deepest nesting that the server runs."
    argument :default_page_size, Integer, required: true,
             description: "The page size of a connection when a query gives no first or last."
    argument :max_page_size, Integer, required: true,
             description: "The largest page that a connection returns."
  end
end
