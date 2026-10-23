# frozen_string_literal: true

module McpTools
  # Runs a query against the public catalog GraphQL schema (POST
  # /api/v1/graphql), with the same depth, cost, page, and semantic search
  # limits. The schema has no mutations and no user data. The request goes in
  # the context, so a semantic search counts against the user of the token.
  class CatalogGraphql < BaseTool
    MAX_QUERY_LENGTH = 10_000

    tool_name "catalog_graphql"
    title "Query the catalog with GraphQL"
    description "Runs a read-only GraphQL query on the Wentworth course catalog, for nested data in one call. " \
                "The schema is at https://calendar.witcc.dev/docs/api/schema.graphql. Root fields: terms, term, " \
                "subjects, sections(filter:, first:, after:), section(crn:, termUid:), instructors, reviews. " \
                "Prefer the other catalog tools for simple lookups."
    requires_scope "catalog"
    academic_planning :sections, :course_details
    input_schema(
      properties: {
        query:          { type: "string", description: "The GraphQL query document." },
        variables:      { type: "object", description: "Values for the query's variables." },
        operation_name: { type: "string", description: "The operation to run when the document has several." }
      },
      required: [ "query" ]
    )
    # A GraphQL response: data has the shape of the query, so it stays open.
    output_schema(
      Schemas.object(
        {
          data:       Schemas.nullable({ type: "object", additionalProperties: true }),
          errors:     Schemas.array({ type: "object", properties: { message: Schemas::STRING }, additionalProperties: true }),
          extensions: { type: "object", additionalProperties: true }
        },
        optional: %i[data errors extensions]
      )
    )

    def perform(query:, variables: nil, operation_name: nil)
      raise ToolError, "query is longer than #{MAX_QUERY_LENGTH} characters" if query.length > MAX_QUERY_LENGTH

      result = CatalogSchema.execute(
        query,
        variables:      variables.to_h.deep_stringify_keys,
        operation_name: operation_name,
        context:        { request: request }
      ).to_h

      raise ToolError, result["errors"].pluck("message").join("; ") if result["data"].nil? && result["errors"].present?

      result
    end
  end
end
