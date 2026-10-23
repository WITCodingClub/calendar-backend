# frozen_string_literal: true

module Catalog
  # Finds the degree programs of one catalog year (RequirementSet rows). The
  # REST controller and the MCP tools list_programs and degree_requirements
  # use this object. docs/degree-requirements.md describes the data.
  class ProgramQuery
    class FilterError < ::Catalog::FilterError; end

    YEAR_SPAN = /\A(\d{4})(?:\s*[-\u2013\u2014]\s*(\d{2}|\d{4}))?\z/
    TERM_NAME = /\A(fall|spring|summer)\s+(\d{4})\z/i

    # The first year of a catalog year, from "2024", "2024-2025", "2024-25",
    # or a term name: a catalog year starts in the fall, so "Spring 2024" is
    # in 2023-2024. nil for anything else, and for a span whose years do not
    # follow each other.
    def self.start_year(value)
      text = value.to_s.strip
      if (term = TERM_NAME.match(text))
        year = term[2].to_i
        return term[1].casecmp?("fall") ? year : year - 1
      end

      match = YEAR_SPAN.match(text)
      return nil if match.nil?

      start = match[1].to_i
      return start if match[2].nil?

      ending = match[2].to_i
      ending += start - (start % 100) if match[2].length == 2
      ending += 100 if match[2].length == 2 && ending <= start # 2099-00
      ending == start + 1 ? start : nil
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
      if start_year.nil?
        raise FilterError, "catalog_year must be a catalog year such as 2024-2025, or the term a program started, " \
                           "such as Spring 2024"
      end

      catalog_years.find_by(start_year: start_year)
    end

    # The programs that the last import of the year saw. A program that left
    # the catalog keeps its stored set, so the list leaves it out.
    #
    # @return [ActiveRecord::Relation<RequirementSet>]
    def call(catalog_year:, kind: nil, level: nil, q: nil)
      relation = catalog_year.requirement_sets.joins(:degree_program).includes(:catalog_year, degree_program: :parent_program)
      relation = relation.where(last_seen_at: RequirementSet.listed_since(catalog_year)..) if catalog_year.imported_at
      relation = relation.where(degree_programs: { kind: validated(kind, DegreeProgram::KINDS, "kind") }) if kind.present?
      relation = relation.where(degree_programs: { level: validated(level, DegreeProgram::LEVELS, "level") }) if level.present?
      q.to_s.split.each do |word|
        pattern = "%#{RequirementSet.sanitize_sql_like(word)}%"
        relation = relation.where("requirement_sets.name ILIKE :p OR degree_programs.slug ILIKE :p", p: pattern)
      end
      relation.order("requirement_sets.name")
    end

    # One program in a catalog year, by slug ("computer-science-bs") or by
    # its exact name ("Computer Science, B.S."), with its plans and lists. It
    # also finds a program that left the catalog (ProgramSerializer gives
    # listed: false), so a student on that program still gets its plan.
    def find(program, catalog_year:)
      relation = catalog_year.requirement_sets.joins(:degree_program).includes(
        :catalog_year, degree_program: :parent_program,
        program_plans: { items: :elective_group }, elective_groups: %i[courses program_plan]
      )
      key = program.to_s.strip.downcase
      relation.find_by(degree_programs: { slug: key }) ||
        relation.where("lower(requirement_sets.name) = ?", key).order(:id).first
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
