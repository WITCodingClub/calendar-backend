# frozen_string_literal: true

module McpTools
  # GET /api/user/next_term_courses (#449).
  class MyNextTermCourses < BaseTool
    tool_name "my_next_term_courses"
    title "My courses for next term"
    description "Lists the courses that the plan of study of each of my programs puts in the term I register " \
                "for next, without the ones I did or take now, and the open rows of earlier plan semesters " \
                "(behind). Each course says if the term has a section of it, and if I meet its prerequisites " \
                "with the courses I did or take now. This is a help for planning, not a degree audit or a " \
                "registration check. Read assumptions in the result."
    requires_scope "programs:read"
    requires_flag FeatureFlags::DEGREE_PLANNING
    academic_planning :degree_requirements, :sections, :course_details
    input_schema(
      properties: {
        term: { type: "string", description: "A Banner term code (202720) or a label (Spring 2027). Leave it " \
                                             "out for the next fall or spring term." }
      }
    )
    output_schema(Schemas::NEXT_TERM_COURSES)

    def perform(term: nil)
      authorize user, :show?

      term_uid = nil
      if term.present?
        term_uid = AcademicProfiles::TermCode.parse(term)
        raise ToolError, "term must be a Banner term code or a label such as Spring 2027." if term_uid.nil?
      end

      AcademicProfiles::NextTermCourses.new(user, term_uid: term_uid).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError => e
      raise ToolError, e.message
    end
  end
end
