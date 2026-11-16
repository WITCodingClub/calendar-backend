# frozen_string_literal: true

module McpTools
  # GET /api/user/programs (#868).
  class MyPrograms < BaseTool
    NO_PROGRAMS_MESSAGE = "WIT Calendar has no programs for this student. The WIT Calendar browser extension reads " \
                          "them from the Student Profile page in LeopardWeb when the student processes a term. " \
                          "Ask the student to open the extension and process a term, or ask them for their " \
                          "program and catalog year. Do not guess them."

    tool_name "my_programs"
    title "My programs"
    description "Lists my majors, minors, concentrations, and certificates, as LeopardWeb shows them, with the " \
                "catalog year of each. A student follows the requirements of that catalog year, so pass program " \
                "and catalog_year to degree_requirements. Also lists the programs I plan to take " \
                "(planned_programs, added with update_my_planned_programs), the pathways I plan, such as a 4+1 " \
                "(planned_pathways; each planned program names its pathway), and my ended programs, such as a major " \
                "I changed. program is null when WIT Calendar cannot link the program to the degree catalog."
    requires_scope "programs:read"
    requires_flag FeatureFlags::DEGREE_PLANNING
    academic_planning :degree_requirements
    input_schema(properties: {})
    # message is there only when the student has no programs.
    output_schema(
      Schemas.object(
        Schemas::STUDENT_PROGRAMS_PROPERTIES.merge(message: Schemas::STRING),
        optional: %i[message]
      )
    )

    def perform
      authorize user, :show?

      result = StudentProgramsSerializer.new(user).as_json
      return result unless result.values_at(:programs, :planned_programs, :ended_programs).all?(&:empty?)

      result.merge(message: NO_PROGRAMS_MESSAGE)
    end
  end
end
