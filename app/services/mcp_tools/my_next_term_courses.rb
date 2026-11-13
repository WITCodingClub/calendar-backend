# frozen_string_literal: true

module McpTools
  # GET /api/user/next_term_courses (#449).
  class MyNextTermCourses < BaseTool
    tool_name "my_next_term_courses"
    title "My courses for next term"
    description "Lists the courses that the plan of study of each of my programs puts in the term I register " \
                "for next, without the ones I did or take now, and the open rows of earlier plan semesters " \
                "(behind). Each course says if the term has a section of it, and if I meet its prerequisites " \
                "with the courses I did or take now. Each course also has its title, description, credit " \
                "hours, and the terms it is usually offered. An elective slot has its elective list. " \
                "missing_in_plan lists the missing prerequisites that a planned or behind row of the term " \
                "names: tell me to take those first. To plan a later term, pass assume_plans to count the " \
                "courses of my saved registration plans before the term as passed, or assume to name courses " \
                "to count as passed. The result lists them in assumed. This is a help for planning, not a " \
                "degree audit or a registration check. Read assumptions in the result."
    requires_scope "programs:read"
    requires_flag FeatureFlags::DEGREE_PLANNING
    academic_planning :degree_requirements, :sections, :course_details
    input_schema(
      properties: {
        term:         { type: "string", description: "A Banner term code (202720) or a label (Spring 2027). Leave " \
                                                     "it out for the next fall or spring term." },
        assume:       {
          type:        "array",
          items:       { type: "string" },
          maxItems:    AcademicProfiles::AssumedCourses::MAX_CODES,
          description: "Course codes (COMP3350 or COMP 3350) to count as passed before the term, with a C or better."
        },
        assume_plans: {
          type:        "boolean",
          description: "Also count as passed the courses of my saved registration plans for the terms after " \
                       "the current term and before the term."
        }
      }
    )
    output_schema(Schemas::NEXT_TERM_COURSES)

    def perform(term: nil, assume: nil, assume_plans: false)
      authorize user, :show?

      term_uid = nil
      if term.present?
        term_uid = AcademicProfiles::TermCode.parse(term)
        raise ToolError, "term must be a Banner term code or a label such as Spring 2027." if term_uid.nil?
      end

      assume = AcademicProfiles::AssumedCourses.parse(assume)
      AcademicProfiles::NextTermCourses.new(user, term_uid: term_uid, assume: assume, assume_plans: assume_plans == true).call
    rescue AcademicProfiles::AssumedCourses::InvalidCodesError, AcademicProfiles::DegreeProgress::NoProgramError => e
      raise ToolError, e.message
    end
  end
end
