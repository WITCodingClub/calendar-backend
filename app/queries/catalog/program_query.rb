# frozen_string_literal: true

module Catalog
  # Finds the degree programs of one catalog year (RequirementSet rows). The
  # REST controller and the MCP tools list_programs and degree_requirements
  # use this object. docs/degree-requirements.md describes the data.
  class ProgramQuery
    class FilterError < ::Catalog::FilterError; end

    # "2024", 2024, or "2024-2025" to 2024; anything else to nil.
    def self.start_year(value)
      value.to_s.strip[/\A(\d{4})(?:\s*-\s*\d{4})?\z/, 1]&.to_i
    end

    # The imported catalog years, newest first.
    def catalog_years
      CatalogYear.where(status: "imported").order(start_year: :desc)
    end

    # The catalog year for a parameter, or the newest imported year when the
    # parameter is blank. Raises FilterError for a value that is not a year.
    def catalog_year(value)
      return catalog_years.first if value.blank?

      start_year = self.class.start_year(value)
      raise FilterError, "catalog_year must be a year such as 2024 or 2024-2025" if start_year.nil?

      catalog_years.find_by(start_year: start_year)
    end

    # @return [ActiveRecord::Relation<RequirementSet>]
    def call(catalog_year:, kind: nil, level: nil, q: nil)
      relation = catalog_year.requirement_sets.joins(:degree_program).includes(:catalog_year, degree_program: :parent_program)
      relation = relation.where(degree_programs: { kind: validated(kind, DegreeProgram::KINDS, "kind") }) if kind.present?
      relation = relation.where(degree_programs: { level: validated(level, DegreeProgram::LEVELS, "level") }) if level.present?
      q.to_s.split.each do |word|
        pattern = "%#{RequirementSet.sanitize_sql_like(word)}%"
        relation = relation.where("requirement_sets.name ILIKE :p OR degree_programs.slug ILIKE :p", p: pattern)
      end
      relation.order("requirement_sets.name")
    end

    # One program in a catalog year, by slug ("computer-science-bs") or by
    # its exact name ("Computer Science, B.S."), with its plans and lists.
    def find(program, catalog_year:)
      relation = catalog_year.requirement_sets.joins(:degree_program).includes(
        :catalog_year, degree_program: :parent_program,
        program_plans: :items, elective_groups: %i[courses program_plan]
      )
      relation.find_by(degree_programs: { slug: program.to_s.strip.downcase }) ||
        relation.where("lower(requirement_sets.name) = ?", program.to_s.strip.downcase).first
    end

    private

    def validated(value, allowed, name)
      values = Array(value).map { |v| v.to_s.strip.downcase }
      unknown = values - allowed.values
      raise FilterError, "#{name} must be one of #{allowed.values.join(', ')}" if unknown.any?

      values
    end
  end
end
