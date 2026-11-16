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
      properties: {
        q:        { type: "string", description: "A name, for example \"ada lovelace\". With semantic, what they teach." },
        semantic: { type: "boolean", description: "Rank q by meaning instead of by the name." },
        term_uid: { type: "integer", description: "Only instructors who teach in this term." },
        page:     PAGE_SCHEMA,
        per_page: per_page_schema(:instructors)
      }
    )
    output_schema(Schemas.object(instructors: Schemas.array(Schemas::INSTRUCTOR), meta: Schemas::PAGE_META))

    def perform(q: nil, semantic: false, term_uid: nil, page: nil, per_page: nil)
      spend_semantic_search!(q, semantic)
      page  = Catalog::Page.new(:instructors, page: page, per_page: per_page)
      scope = Catalog::InstructorQuery.new.call(term_uid: term_uid, q: q, semantic: semantic)

      {
        instructors: page.of(scope).map { |person| Catalog::InstructorSerializer.new(person).as_json },
        meta:        page.meta(scope.count)
      }
    end
  end
end
