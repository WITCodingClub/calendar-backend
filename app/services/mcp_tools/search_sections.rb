# frozen_string_literal: true

module McpTools
  # It takes every filter of Catalog::SectionQuery.
  class SearchSections < BaseTool
    DAY_SCHEMA = { type: "string", enum: Catalog::ScheduleRules::DAYS }.freeze

    tool_name "search_sections"
    title "Search course sections"
    description "Searches the Wentworth course catalog for sections. Combine filters to narrow the list. " \
                "Set semantic to true to rank q by meaning, for example q: \"intro to machine learning\". " \
                "Without term_uid it searches the current term. Use it for \"when does COMP 2350 meet next " \
                "semester\". For \"which sections have open seats\", set open_only to true, and add include_waitlist " \
                "to also keep full sections whose waitlist has room. During registration, seat counts can be up to 30 minutes old. Not every section has a waitlist: a " \
                "waitlist capacity of 0 means none, and null means WIT Calendar does not know yet. For a full section with a waitlist, the student joins it " \
                "before they ask for a capacity override. A Technical or HSS elective can be missing until its school sends the list: " \
                "list_term_electives gives the lists the schools sent. For an elective that is still missing, the " \
                "student asks the dean or associate dean of their school."
    requires_scope "catalog"
    meta CatalogApp.tool_meta
    academic_planning :sections
    input_schema(
      properties: {
        term_uid:          TERM_SCHEMA,
        q:                 { type: "string", description: "Words to find in the title, subject, or description." },
        semantic:          { type: "boolean", description: "Rank q by meaning instead of by the literal words." },
        subject:           { type: "array", items: { type: "string" }, description: "Subject codes, for example COMP or MATH." },
        course_number:     { type: "array", items: { type: "integer" }, description: "Course numbers, for example 1000." },
        crns:              { type: "array", items: { type: "integer" }, description: "Section CRNs." },
        pub_ids:           { type: "array", items: { type: "string" }, description: "Section public ids." },
        schedule_types:    { type: "array", items: { type: "string" }, description: "For example lecture or LEC." },
        meets_on:          { type: "array", items: DAY_SCHEMA, description: "Keep sections that meet on any of these days." },
        free_days:         { type: "array", items: DAY_SCHEMA, description: "Drop sections that meet on any of these days." },
        begins_after:      { type: "string", description: "Drop sections with any meeting before this time. HH:MM, 24-hour." },
        ends_before:       { type: "string", description: "Drop sections with any meeting after this time. HH:MM, 24-hour." },
        credit_hours:      { type: "array", items: { type: "integer" }, description: "Credit hours, for example 4." },
        instructor:        { type: "string", description: "Part of an instructor name." },
        include_cancelled: { type: "boolean", description: "Also return cancelled sections." },
        open_only:         { type: "boolean", description: "Keep only sections with a free seat. Drops sections with no seat data." },
        include_waitlist:  { type: "boolean", description: "With open_only, also keep full sections whose waitlist has room." },
        page:              PAGE_SCHEMA,
        per_page:          per_page_schema(:sections)
      }
    )
    output_schema(
      Schemas.object(
        term_uid: Schemas::INTEGER,
        sections: Schemas.array(Schemas::SECTION),
        meta:     Schemas::PAGE_META
      )
    )

    def perform(term_uid: nil, page: nil, per_page: nil, **filters)
      term = find_term(term_uid)
      spend_semantic_search!(filters[:q], filters[:semantic])
      page     = Catalog::Page.new(:sections, page: page, per_page: per_page)
      relation = Catalog::SectionQuery.new.call(term_uid: term.uid, **filters.compact)
      sections = page.of(Catalog::SectionQuery.with_associations(relation))

      {
        term_uid: term.uid,
        sections: Catalog::SectionSerializer.collection(sections),
        meta:     page.meta(relation.count("DISTINCT courses.id"))
      }
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
