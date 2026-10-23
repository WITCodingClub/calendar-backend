# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/sections. GraphQL: sections. It takes every filter of
  # Catalog::SectionQuery.
  class SearchSections < BaseTool
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE     = 100
    DAYS             = Catalog::SectionQuery::DAYS.keys.freeze

    tool_name "search_sections"
    title "Search course sections"
    description "Searches the Wentworth course catalog for sections. Combine filters to narrow the list. " \
                "Set semantic to true to rank q by meaning, for example q: \"intro to machine learning\". " \
                "Without term_uid it searches the current term."
    requires_scope "catalog"
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
        meets_on:          { type: "array", items: { type: "string", enum: DAYS }, description: "Keep sections that meet on any of these days." },
        free_days:         { type: "array", items: { type: "string", enum: DAYS }, description: "Drop sections that meet on any of these days." },
        begins_after:      { type: "string", description: "Drop sections with any meeting before this time. HH:MM, 24-hour." },
        ends_before:       { type: "string", description: "Drop sections with any meeting after this time. HH:MM, 24-hour." },
        credit_hours:      { type: "array", items: { type: "integer" }, description: "Credit hours, for example 4." },
        instructor:        { type: "string", description: "Part of an instructor name." },
        include_cancelled: { type: "boolean", description: "Also return cancelled sections." },
        page:              PAGE_SCHEMA,
        per_page:          { type: "integer", minimum: 1, maximum: MAX_PER_PAGE, description: "Default #{DEFAULT_PER_PAGE}." }
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
      page, per_page = page_params(page, per_page, default: DEFAULT_PER_PAGE, max: MAX_PER_PAGE)

      relation = Catalog::SectionQuery.new.call(term_uid: term.uid, **filters.compact)
      total    = relation.count("DISTINCT courses.id")
      sections = Catalog::SectionQuery.with_associations(relation).page(page).per(per_page)

      {
        term_uid: term.uid,
        sections: serialize(sections.to_a),
        meta:     page_meta(page, per_page, total)
      }
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end

    private

    def serialize(sections)
      catalog_courses = Catalog::CourseQuery.for_sections(sections)
      sections.map { |course| Catalog::SectionSerializer.new(course, catalog_courses: catalog_courses).as_json }
    end
  end
end
