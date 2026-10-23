# frozen_string_literal: true

module McpTools
  # GET /api/user/course_history.
  class MyCourseHistory < BaseTool
    tool_name "my_course_history"
    title "My course history"
    description "Lists every term I have processed in WIT Calendar, newest first, with my courses in each term: " \
                "the professor and the weekly meeting times and rooms. Use it to find the classes I took before. " \
                "A term that I did not process in the extension is not in the list, so the history can have gaps."
    requires_scope "schedule:read"
    academic_planning :sections
    input_schema(properties: {})
    # Courses::HistoryBuilder.
    output_schema(
      Schemas.object(
        terms: Schemas.array(
          Schemas.object(
            uid:     Schemas::INTEGER,
            pub_id:  Schemas::STRING,
            name:    Schemas::STRING,
            season:  Schemas::STRING,
            year:    Schemas::INTEGER,
            courses: Schemas.array(Schemas::MY_COURSE_IN_TERM)
          )
        )
      )
    )

    def perform
      authorize user, :show?

      Courses::HistoryBuilder.new(user).build
    end
  end
end
