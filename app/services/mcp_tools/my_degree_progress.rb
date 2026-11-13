# frozen_string_literal: true

module McpTools
  # GET /api/user/degree_progress (#799).
  class MyDegreeProgress < BaseTool
    tool_name "my_degree_progress"
    title "My degree progress"
    description "Compares the requirements of my programs with the courses I took or take in every term I " \
                "processed in WIT Calendar. Marks each requirement of the plan of study as done, in_progress, " \
                "or open, and lists the open ones. Each course row has the course title, description, credit " \
                "hours, and the terms it is usually offered. An elective slot has its elective list and the " \
                "course that fills it. Each plan row has its planned_term (the real term of its plan " \
                "semester) and behind (open, and its term already started). Each program has a summary: its " \
                "total credits, school, department, the credits I earned and take now in courses that fill " \
                "a row of that program, the credits and codes of my other courses (not_counted), and the " \
                "co-op semesters. Each program also has its start_term, a timeline of the plan semesters with their " \
                "real terms (when: past, current, registering, or future; estimated after year 2; co_op), and " \
                "expected_end. A planned program or a program argument has no start term, so it has no " \
                "timeline. The hss entry of a program has each HSS category with a hint (the subjects or " \
                "courses that meet it), the English sequence courses and their credits, each course that " \
                "counts toward HSS with its category, and the open HSS slots with their planned terms. " \
                "Each program has total_credits and school. A program with no plan of study, such as " \
                "a minor, has lists: each elective list with its minimum and its courses, each course with " \
                "its status, the term I took it, and major_term (its planned term in one of my active " \
                "programs, or null). This is a help for planning, not a degree audit: it does not know substitutions, " \
                "transfer credit, or AP credit, and the history can have gaps. The student's official degree " \
                "audit is Stellic. Without arguments it checks each of my programs in its own catalog year. " \
                "Read assumptions in the result."
    requires_scope "programs:read"
    requires_flag FeatureFlags::DEGREE_PLANNING
    academic_planning :degree_requirements, :sections, :course_details
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
