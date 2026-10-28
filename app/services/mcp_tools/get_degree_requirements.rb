# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/programs/:slug. The class is not named
  # DegreeRequirements, because that module holds the catalog import.
  class GetDegreeRequirements < BaseTool
    tool_name "degree_requirements"
    title "Get degree requirements"
    description "Gets what one program requires in one catalog year of the Wentworth academic catalog: each plan " \
                "of study (such as the four-year and the three-year plan) semester by semester, with required " \
                "courses, choices between courses, and elective slots, and the elective lists that the slots draw " \
                "from, with their minimums. Call list_programs to find the slug. This is the published catalog, " \
                "not a degree audit: a student's own audit (Stellic) decides which courses count. A course " \
                "substitution or transfer credit for a requirement needs approval from the program director, " \
                "the dean's office of the school, or both."
    requires_scope "catalog"
    academic_planning :degree_requirements, :course_details
    input_schema(
      properties: {
        program:      { type: "string", description: "The program slug from list_programs, for example " \
                                                      "computer-science-bs, or its exact name." },
        catalog_year: ListPrograms::CATALOG_YEAR_SCHEMA
      },
      required: [ "program" ]
    )
    output_schema(Schemas::PROGRAM)

    def perform(program:, catalog_year: nil)
      query = Catalog::ProgramQuery.new
      year = ListPrograms.find_catalog_year(query, catalog_year)
      set = query.find(program, catalog_year: year)
      raise ToolError, "No program #{program} in the #{year.name} catalog. Call list_programs to find the slug." if set.nil?

      Catalog::ProgramSerializer.new(set).as_json
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
