# frozen_string_literal: true

module McpTools
  class SimilarInstructors < BaseTool
    tool_name "similar_instructors"
    title "Similar instructors"
    description "Lists instructors who teach something close to what one instructor teaches."
    requires_scope "catalog"
    input_schema(
      properties: {
        instructor_id: { type: "string", description: "The instructor pub_id." },
        limit:         SIMILAR_LIMIT_SCHEMA
      },
      required: [ "instructor_id" ]
    )
    output_schema(Schemas.object(instructor_id: Schemas::STRING, instructors: Schemas.array(Schemas::INSTRUCTOR)))

    def perform(instructor_id:, limit: nil)
      faculty = Catalog::InstructorQuery.find!(instructor_id)
      people  = faculty.similar_instructors(limit: Embeddable.similar_limit(limit)).includes(:rating_distribution)

      { instructor_id: faculty.public_id, instructors: people.map { |person| Catalog::InstructorSerializer.new(person).as_json } }
    end
  end
end
