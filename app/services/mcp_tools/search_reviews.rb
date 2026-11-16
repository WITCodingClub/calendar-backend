# frozen_string_literal: true

module McpTools
  class SearchReviews < BaseTool
    tool_name "search_reviews"
    title "Search instructor reviews"
    description "Searches RateMyProfessors reviews of Wentworth instructors, newest first. " \
                "Set semantic to true to find reviews by meaning, for example q: \"lots of group projects\"."
    requires_scope "catalog"
    input_schema(
      properties: CatalogFilters.properties(Catalog::ReviewQuery).merge(page: PAGE_SCHEMA, per_page: per_page_schema(:reviews))
    )
    output_schema(
      Schemas.object(
        reviews: Schemas.array(Schemas::REVIEW),
        meta:    Schemas.object(Schemas::PAGE_META[:properties].merge(source: Schemas::STRING))
      )
    )

    def perform(page: nil, per_page: nil, **arguments)
      spend_semantic_search!(arguments[:q], arguments[:semantic])
      list = Catalog::ListRequest.new(:reviews, CatalogFilters.filters(Catalog::ReviewQuery, arguments),
                                      page: page, per_page: per_page, surface: :mcp)

      { reviews: list.rows, meta: list.meta }
    end
  end
end
