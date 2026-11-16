# frozen_string_literal: true

module McpTools
  class SearchReviews < BaseTool
    tool_name "search_reviews"
    title "Search instructor reviews"
    description "Searches RateMyProfessors reviews of Wentworth instructors, newest first. " \
                "Set semantic to true to find reviews by meaning, for example q: \"lots of group projects\"."
    requires_scope "catalog"
    input_schema(
      properties: {
        instructor_id: { type: "string", description: "Only reviews of this instructor: the pub_id from search_instructors, not a name." },
        q:             { type: "string", description: "Words to find in the comment or the course." },
        semantic:      { type: "boolean", description: "Rank q by meaning instead of by the literal words." },
        sentiment:     { type: "string", enum: Catalog::ReviewQuery::SENTIMENTS },
        page:          PAGE_SCHEMA,
        per_page:      per_page_schema(:reviews)
      }
    )
    output_schema(
      Schemas.object(
        reviews: Schemas.array(Schemas::REVIEW),
        meta:    Schemas.object(Schemas::PAGE_META[:properties].merge(source: Schemas::STRING))
      )
    )

    def perform(instructor_id: nil, q: nil, semantic: false, sentiment: nil, page: nil, per_page: nil)
      spend_semantic_search!(q, semantic)
      page     = Catalog::Page.new(:reviews, page: page, per_page: per_page)
      relation = Catalog::ReviewQuery.new.call(instructor: instructor_id, q: q, semantic: semantic, sentiment: sentiment)
      reviews  = page.of(Catalog::ReviewQuery.with_associations(relation))

      {
        reviews: reviews.map { |review| Catalog::ReviewSerializer.new(review).as_json },
        meta:    page.meta(relation.count).merge(source: Catalog::ReviewSerializer::SOURCE)
      }
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
