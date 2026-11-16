# frozen_string_literal: true

module McpTools
  # The input schema and the arguments of an MCP catalog search, made from the
  # filters that the query object declares (Catalog::Filters), so a tool takes
  # the same filters as the REST API and the GraphQL schema.
  module CatalogFilters
    DAY_SCHEMA = { type: "string", enum: Catalog::ScheduleRules::DAYS }.freeze

    SCHEMAS = {
      string:         { type: "string" },
      integer:        { type: "integer" },
      time:           { type: "string" },
      enum:           { type: "string" },
      flag:           { type: "boolean" },
      strict_flag:    { type: "boolean" },
      strings:        { type: "array", items: { type: "string" } },
      integers:       { type: "array", items: { type: "integer" } },
      days:           { type: "array", items: DAY_SCHEMA },
      schedule_types: { type: "array", items: { type: "string" } }
    }.freeze

    module_function

    # The input schema properties of the query's filters, by MCP name.
    def properties(query)
      query.filters.to_h do |filter|
        schema = SCHEMAS.fetch(filter.type).merge(description: filter.description)
        schema[:enum] = filter.values if filter.values
        [ filter.mcp, schema ]
      end
    end

    # The tool's arguments, by MCP name, as the query's filters.
    def filters(query, arguments)
      query.filters.to_h { |filter| [ filter.name, arguments[filter.mcp] ] }.compact
    end
  end
end
