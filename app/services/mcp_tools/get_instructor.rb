# frozen_string_literal: true

module McpTools
  class GetInstructor < BaseTool
    tool_name "get_instructor"
    title "Get an instructor"
    description "Gets one instructor by public id, with everything from RateMyProfessor that WIT Calendar stores: " \
                "the average rating and difficulty, the rating distribution, the top tags, and the newest reviews. " \
                "With term_uid it also lists the sections the instructor teaches in that term. " \
                "Call search_reviews for more reviews."
    requires_scope "catalog"
    meta CatalogApp.tool_meta
    input_schema(
      properties: {
        instructor_id: { type: "string", description: "The instructor pub_id, for example fac_kw7coe30." },
        term_uid:      { type: "integer", description: "Also list the sections taught in this term." }
      },
      required: [ "instructor_id" ]
    )
    output_schema(Schemas::INSTRUCTOR_DETAIL)

    def perform(instructor_id:, term_uid: nil)
      term = term_uid && Term.find_by_uid!(term_uid)
      Catalog::InstructorDetailSerializer.new(Catalog::InstructorQuery.find!(instructor_id), term: term).as_json
    end
  end
end
