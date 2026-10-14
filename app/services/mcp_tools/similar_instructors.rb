# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/instructors/:pub_id/similar.
  class SimilarInstructors < BaseTool
    tool_name "similar_instructors"
    title "Similar instructors"
    description "Lists instructors who teach something close to what one instructor teaches."
    input_schema(
      properties: {
        instructor_id: { type: "string", description: "The instructor pub_id." },
        limit:         { type: "integer", minimum: 1, maximum: Embeddable::MAX_SIMILAR_LIMIT }
      },
      required: [ "instructor_id" ]
    )

    def perform(instructor_id:, limit: nil)
      faculty = find_instructor(instructor_id)
      limit   = limit_value(limit, default: Embeddable::DEFAULT_SIMILAR_LIMIT, max: Embeddable::MAX_SIMILAR_LIMIT)
      people  = faculty.similar_instructors(limit: limit).includes(:rating_distribution)

      { instructor_id: faculty.public_id, instructors: people.map { |person| Catalog::InstructorSerializer.new(person).as_json } }
    end
  end
end
