# frozen_string_literal: true

module McpTools
  # GET /api/user/finals.
  class MyFinals < BaseTool
    tool_name "my_finals"
    title "My final exams"
    description "Lists the final exams for my courses in one term: date, time, and room."
    requires_scope "schedule:read"
    input_schema(properties: { term_uid: TERM_SCHEMA })

    def perform(term_uid: nil)
      authorize user, :show?
      term = find_term(term_uid)

      exams = Courses::FinalExamsQuery.new(user, term).call
      { term_uid: term.uid, finals: exams.map { |exam| EnrolledFinalExamSerializer.new(exam).as_json } }
    end
  end
end
