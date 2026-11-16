# frozen_string_literal: true

module McpTools
  class SearchInstructors < BaseTool
    tool_name "search_instructors"
    title "Search instructors"
    description "Finds the Wentworth instructors who teach at least one section, by name or by meaning, " \
                "with department, school, and RateMyProfessor ratings. Use it for \"is Professor X " \
                "good\" and \"who teaches networking\"."
    requires_scope "catalog"
    input_schema(
      properties: CatalogFilters.properties(Catalog::InstructorQuery).merge(page: PAGE_SCHEMA, per_page: per_page_schema(:instructors))
    )
    output_schema(Schemas.object(instructors: Schemas.array(Schemas::INSTRUCTOR), meta: Schemas::PAGE_META))

    def perform(page: nil, per_page: nil, **arguments)
      spend_semantic_search!(arguments[:q], arguments[:semantic])
      list = Catalog::ListRequest.new(:instructors, CatalogFilters.filters(Catalog::InstructorQuery, arguments),
                                      page: page, per_page: per_page, surface: :mcp)

      { instructors: list.rows, meta: list.meta }
    end
  end
end
