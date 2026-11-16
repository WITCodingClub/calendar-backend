# frozen_string_literal: true

module McpTools
  class SimilarSections < BaseTool
    tool_name "similar_sections"
    title "Similar sections"
    description "Lists sections that teach something close to one section. The list is empty until the " \
                "course has a vector, which a nightly job writes."
    requires_scope "catalog"
    meta CatalogApp.tool_meta
    academic_planning :sections
    input_schema(
      properties: {
        crn:      { type: "integer", description: "The section CRN." },
        term_uid: TERM_SCHEMA,
        limit:    SIMILAR_LIMIT_SCHEMA
      },
      required: [ "crn" ]
    )
    output_schema(Schemas.object(crn: Schemas::INTEGER, sections: Schemas.array(Schemas::SECTION)))

    def perform(crn:, term_uid: nil, limit: nil)
      course  = Catalog::SectionQuery.find!(crn, find_term(term_uid).uid)
      similar = Catalog::SectionQuery.with_associations(course.similar_sections(limit: Embeddable.similar_limit(limit)))

      { crn: course.crn, sections: Catalog::SectionSerializer.collection(similar) }
    end
  end
end
