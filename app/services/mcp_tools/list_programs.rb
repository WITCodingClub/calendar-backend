# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/programs.
  class ListPrograms < BaseTool
    CATALOG_YEAR_SCHEMA = {
      type:        "string",
      description: "The catalog year, for example 2024-2025, or the term a program started, for example Spring " \
                   "2024. A student follows the catalog of the term they started their program in, and a catalog " \
                   "year starts in the fall, so Spring 2024 is in 2023-2024. A bare year such as 2024 is the first " \
                   "year: 2024-2025. Leave it out for the newest catalog."
    }.freeze

    tool_name "list_programs"
    title "List degree programs"
    description "Lists the degree programs in one catalog year of the Wentworth academic catalog: majors, minors, " \
                "concentrations, certificates, and graduate degrees, with the slug that degree_requirements takes. " \
                "Also lists the catalog years WIT Calendar has."
    requires_scope "catalog"
    academic_planning :degree_requirements
    input_schema(
      properties: {
        catalog_year: CATALOG_YEAR_SCHEMA,
        kind:         { type: "string", enum: DegreeProgram::KINDS.values, description: "Only programs of this kind." },
        level:        { type: "string", enum: DegreeProgram::LEVELS.values, description: "Only programs of this level." },
        q:            { type: "string", description: "Words in the program name, for example computer science." }
      }
    )
    output_schema(
      Schemas.object(
        catalog_year:  Schemas::STRING,
        catalog_years: Schemas::STRINGS,
        programs:      Schemas.array(Schemas::PROGRAM_SUMMARY)
      )
    )

    def perform(catalog_year: nil, kind: nil, level: nil, q: nil)
      query = Catalog::ProgramQuery.new
      year = find_catalog_year(query, catalog_year)
      programs = query.call(catalog_year: year, kind: kind, level: level, q: q)

      { catalog_year: year.name, catalog_years: query.catalog_years.map(&:name),
        programs: programs.map { |set| Catalog::ProgramSerializer.summary(set) } }
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end

    # The same lookup for degree_requirements.
    def self.find_catalog_year(query, value)
      year = query.catalog_year(value)
      return year if year

      years = query.catalog_years.map(&:name)
      raise ToolError, "WIT Calendar has no degree program data yet." if years.empty?

      raise ToolError, "No #{value} catalog. WIT Calendar has these catalog years: #{years.join(', ')}. Catalogs " \
                       "before 2019-2020 are not imported yet."
    end

    private

    def find_catalog_year(query, value) = self.class.find_catalog_year(query, value)
  end
end
