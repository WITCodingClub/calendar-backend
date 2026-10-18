# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/sections/:crn/similar.
  class SimilarSections < BaseTool
    tool_name "similar_sections"
    title "Similar sections"
    description "Lists sections that teach something close to one section. The list is empty until the " \
                "section has a vector, which a nightly job writes."
    requires_scope "catalog"
    input_schema(
      properties: {
        crn:      { type: "integer", description: "The section CRN." },
        term_uid: TERM_SCHEMA,
        limit:    { type: "integer", minimum: 1, maximum: Embeddable::MAX_SIMILAR_LIMIT }
      },
      required: [ "crn" ]
    )

    def perform(crn:, term_uid: nil, limit: nil)
      course = find_section(crn, term_uid)
      limit  = limit_value(limit, default: Embeddable::DEFAULT_SIMILAR_LIMIT, max: Embeddable::MAX_SIMILAR_LIMIT)
      similar = Catalog::SectionQuery.with_associations(course.similar_sections(limit: limit)).to_a
      catalog_courses = Catalog::CourseQuery.for_sections(similar)

      { crn: course.crn, sections: similar.map { |section| Catalog::SectionSerializer.new(section, catalog_courses: catalog_courses).as_json } }
    end
  end
end
