# frozen_string_literal: true

module McpTools
  # GET /api/user/degree_progress (#799).
  class MyDegreeProgress < BaseTool
    tool_name "my_degree_progress"
    title "My degree progress"
    description "Compares the requirements of my programs with the courses I took or take in every term I " \
                "processed in WIT Calendar. Marks each requirement of the plan of study as done, in_progress, " \
                "or open, and lists the open ones. This is a help for planning, not a degree audit: it does not " \
                "know substitutions, transfer credit, or AP credit, and the history can have gaps. The " \
                "student's official degree audit is Stellic. Without arguments it checks each of my programs " \
                "in its own catalog year. Read assumptions in the result."
    requires_scope "programs:read"
    academic_planning :degree_requirements, :sections
    input_schema(
      properties: {
        program:      { type: "string", description: "A program slug from list_programs, to check that program in " \
                                                      "place of my own programs, for example a minor I think about." },
        catalog_year: ListPrograms::CATALOG_YEAR_SCHEMA.merge(
          description: "With program: the catalog year. Leave it out for the catalog year of my own program with " \
                       "that slug, or else the newest catalog."
        ),
        plan:         { type: "string", description: "With program: the plan name, for example Three Year " \
                                                      "Program. Leave it out for the standard plan." }
      }
    )
    output_schema(Schemas::DEGREE_PROGRESS)

    def perform(program: nil, catalog_year: nil, plan: nil)
      authorize user, :show?
      raise ToolError, "catalog_year needs program." if catalog_year.present? && program.blank?
      raise ToolError, "plan needs program." if plan.present? && program.blank?

      AcademicProfiles::DegreeProgress.new(user, program: program, catalog_year: catalog_year, plan: plan).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError, Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
