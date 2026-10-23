# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/sections/:crn. GraphQL: section.
  class GetSection < BaseTool
    tool_name "get_section"
    title "Get a course section"
    description "Gets one course section by CRN: meeting times, rooms, instructors, seats, and the final exam. " \
                "It also finds cancelled sections."
    requires_scope "catalog"
    academic_planning
    input_schema(
      properties: {
        crn:      { type: "integer", description: "The section CRN, for example 12345." },
        term_uid: TERM_SCHEMA
      },
      required: [ "crn" ]
    )

    def perform(crn:, term_uid: nil)
      Catalog::SectionSerializer.new(find_section(crn, term_uid)).as_json
    end
  end
end
