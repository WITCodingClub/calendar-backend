# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/courses/:code. GraphQL: course.
  class GetCourse < BaseTool
    tool_name "get_course"
    title "Get a course"
    description "Gets one course by code, such as COMP 2350, from Banner's catalog: the description, the credits, " \
                "the terms it is usually offered, the prerequisites (an and/or tree of courses and placement tests, " \
                "each course with its title), the corequisites, the enrollment restrictions, and the courses it unlocks. " \
                "With term_uid it also lists the course's sections in that term."
    requires_scope "catalog"
    input_schema(
      properties: {
        code:     { type: "string", description: "The course code, for example COMP 2350 or COMP2350." },
        term_uid: { type: "integer", description: "Also list the sections in this term (uid from list_terms)." }
      },
      required: [ "code" ]
    )

    def perform(code:, term_uid: nil)
      raise ToolError, "#{code} is not a course code. Use a subject code and number, for example COMP 2350." unless CatalogCourse.parse_code(code)

      course = Catalog::CourseQuery.new.find(code) || raise(ToolError, "No course #{code}. Call search_courses to find one.")
      term   = term_uid && (Term.find_by(uid: term_uid) || raise(ToolError, "No term with uid #{term_uid}. Call list_terms for the uids."))
      Catalog::CourseSerializer.new(course, term: term).as_json
    end
  end
end
