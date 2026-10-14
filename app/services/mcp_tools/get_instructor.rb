# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/instructors/:pub_id.
  class GetInstructor < BaseTool
    tool_name "get_instructor"
    title "Get an instructor"
    description "Gets one instructor by public id, with RateMyProfessor ratings."
    input_schema(
      properties: { instructor_id: { type: "string", description: "The instructor pub_id, for example fac_kw7coe30." } },
      required:   [ "instructor_id" ]
    )

    def perform(instructor_id:)
      Catalog::InstructorSerializer.new(find_instructor(instructor_id)).as_json
    end
  end
end
