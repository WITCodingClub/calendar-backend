# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/instructors. GraphQL: instructors.
  class SearchInstructors < BaseTool
    DEFAULT_PER_PAGE = 10
    MAX_PER_PAGE     = 50

    tool_name "search_instructors"
    title "Search instructors"
    description "Finds the Wentworth instructors who teach at least one section, by name or by meaning, " \
                "with department, contact details, and RateMyProfessor ratings."
    input_schema(
      properties: {
        q:        { type: "string", description: "A name, for example \"ada lovelace\". With semantic, what they teach." },
        semantic: { type: "boolean", description: "Rank q by meaning instead of by the name." },
        term_uid: { type: "integer", description: "Only instructors who teach in this term." },
        page:     PAGE_SCHEMA,
        per_page: { type: "integer", minimum: 1, maximum: MAX_PER_PAGE, description: "Default #{DEFAULT_PER_PAGE}." }
      }
    )

    def perform(q: nil, semantic: false, term_uid: nil, page: nil, per_page: nil)
      spend_semantic_search!(q, semantic)
      page, per_page = page_params(page, per_page, default: DEFAULT_PER_PAGE, max: MAX_PER_PAGE)

      scope  = Catalog::InstructorQuery.new.call(term_uid: term_uid, q: q, semantic: semantic)
      total  = scope.count
      people = scope.page(page).per(per_page)

      {
        instructors: people.map { |person| Catalog::InstructorSerializer.new(person).as_json },
        meta:        page_meta(page, per_page, total)
      }
    end
  end
end
