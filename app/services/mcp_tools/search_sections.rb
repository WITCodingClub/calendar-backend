# frozen_string_literal: true

module McpTools
  class SearchSections < BaseTool
    tool_name "search_sections"
    title "Search course sections"
    description "Searches the Wentworth course catalog for sections. Combine filters to narrow the list. " \
                "Set semantic to true to rank q by meaning, for example q: \"intro to machine learning\". " \
                "Without term_uid it searches the current term. Use it for \"when does COMP 2350 meet next " \
                "semester\". For \"which sections have open seats\", set open_only to true, and add include_waitlist " \
                "to also keep full sections whose waitlist has room. During registration, #{Catalog::Freshness::SEAT_AGE}. " \
                "Not every section has a waitlist: a waitlist capacity of 0 means none, and null means WIT Calendar " \
                "does not know yet. For a full section with a waitlist, the student joins it " \
                "before they ask for a capacity override. A Technical or HSS elective can be missing until its school sends the list: " \
                "list_term_electives gives the lists the schools sent. For an elective that is still missing, the " \
                "student asks the dean or associate dean of their school."
    requires_scope "catalog"
    meta CatalogApp.tool_meta
    academic_planning :sections
    input_schema(
      properties: CatalogFilters.properties(Catalog::SectionQuery).merge(
        term_uid: TERM_SCHEMA,
        page:     PAGE_SCHEMA,
        per_page: per_page_schema(:sections)
      )
    )
    output_schema(
      Schemas.object(
        term_uid: Schemas::INTEGER,
        sections: Schemas.array(Schemas::SECTION),
        meta:     Schemas::PAGE_META
      )
    )

    def perform(page: nil, per_page: nil, **arguments)
      term = find_term(arguments[:term_uid])
      spend_semantic_search!(arguments[:q], arguments[:semantic])
      filters = CatalogFilters.filters(Catalog::SectionQuery, arguments).merge(term_uid: term.uid)
      list = Catalog::ListRequest.new(:sections, filters, page: page, per_page: per_page, surface: :mcp)

      { term_uid: term.uid, sections: list.rows, meta: list.meta }
    end
  end
end
