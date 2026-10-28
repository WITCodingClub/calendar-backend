# frozen_string_literal: true

module McpTools
  # GET /api/user/finals.
  class MyFinals < BaseTool
    tool_name "my_finals"
    title "My final exams"
    description "Lists the final exams of my Wentworth classes in one term: date, time, and room. Use it for " \
                "\"when is my final\" and \"what is my finals schedule\"."
    requires_scope "schedule:read"
    meta FinalsApp.tool_meta
    academic_planning :finals
    input_schema(properties: { term_uid: TERM_SCHEMA })
    output_schema(
      Schemas.object(
        term_uid:           Schemas::INTEGER,
        schedule_published: Schemas::BOOLEAN,
        finals:             Schemas.array(Schemas::FINAL_EXAM)
      )
    )

    def perform(term_uid: nil)
      authorize user, :show?
      term = find_term(term_uid)

      exams = Courses::FinalExamsQuery.new(user, term).call
      {
        term_uid:           term.uid,
        schedule_published: term.finals_published?,
        finals:             EnrolledFinalExamSerializer.render_collection(exams)
      }
    end
  end
end
