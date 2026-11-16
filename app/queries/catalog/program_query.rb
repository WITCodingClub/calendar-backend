# frozen_string_literal: true

module Catalog
  # Finds the degree programs of one catalog year (RequirementSet rows). The
  # REST controller and the MCP tools list_programs and degree_requirements
  # use this object. docs/degree-requirements.md describes the data.
  #
  # A lookup raises a FilterError with a code, and each surface maps it once:
  # the public API answers 400, or 404 for a NotFoundError
  # (Api::V1::Catalog::ProgramsController), the signed-in API answers 422 with
  # the code (Api::DomainErrors), and an MCP tool gives the message
  # (McpTools::BaseTool).
  class ProgramQuery
    class FilterError < ::Catalog::FilterError
      def code = nil
    end

    class InvalidCatalogYearError < FilterError
      def initialize(msg = "catalog_year must be a catalog year such as 2024-2025, or the term a program started, " \
                           "such as Spring 2024")
        super
      end

      def code = "invalid_catalog_year"
    end

    class NotFoundError < FilterError; end

    # No imported catalog year matches. The message lists the years there
    # are.
    class UnknownCatalogYearError < NotFoundError
      def code = "unknown_catalog_year"
    end

    class UnknownProgramError < NotFoundError
      def initialize(program, catalog_year)
        super("No program #{program} in the #{catalog_year.name} catalog")
      end

      def code = "unknown_program"
    end

    extend Filters
    filter :kind, :strings, "Only programs of these kinds.", values: DegreeProgram::KINDS.values
    filter :level, :strings, "Only programs of these levels.", values: DegreeProgram::LEVELS.values
    filter :q, :string, "Words in the program name, for example computer science."
    filter :parent, :string, "Only the concentrations of this major: its slug, for example construction-management-bs, " \
                             "from my_programs or this list.", param: :parent_program, mcp: :parent_program

    YEAR_SPAN = /\A(\d{4})(?:\s*[-\u2013\u2014]\s*(\d{2}|\d{4}))?\z/

    # The first year of a catalog year, from "2024", "2024-2025", "2024-25",
    # or a term name: a catalog year starts in the fall, so "Spring 2024" is
    # in 2023-2024. nil for anything else, and for a span whose years do not
    # follow each other.
    def self.start_year(value)
      text = value.to_s.strip
      if (term = TermCode::LABEL.match(text))
        return TermCode.catalog_start_year(TermCode.for(term[2].to_i, term[1]))
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

    def catalog_years
      CatalogYear.where(status: "imported").order(start_year: :desc)
    end

    # The catalog year for a parameter, or the newest imported year when the
    # parameter is blank. Raises InvalidCatalogYearError for a value that is
    # not a year.
    def catalog_year(value)
      return catalog_years.first if value.blank?

      start_year = self.class.start_year(value)
      raise InvalidCatalogYearError if start_year.nil?

      catalog_years.find_by(start_year: start_year)
    end

    # catalog_year, or UnknownCatalogYearError when no imported year matches.
    def catalog_year!(value)
      year = catalog_year(value)
      return year if year

      names = catalog_years.map(&:name)
      raise UnknownCatalogYearError, "WIT Calendar has no degree program data yet." if names.empty?

      raise UnknownCatalogYearError, "No #{value.presence || 'imported'} catalog. WIT Calendar has these catalog years: " \
                                     "#{names.join(', ')}."
    end

    # The programs that the last import of the year saw. A program that left
    # the catalog keeps its stored set, so the list leaves it out.
    #
    # @return [ActiveRecord::Relation<RequirementSet>]
    def call(catalog_year:, **filters)
      self.class.check_filters!(filters)
      kind, level, q, parent = filters.values_at(:kind, :level, :q, :parent)
      relation = catalog_year.requirement_sets.joins(:degree_program).includes(:catalog_year, degree_program: :parent_program)
      relation = relation.merge(RequirementSet.listed_in(catalog_year))
      relation = relation.where(degree_programs: { kind: validated(kind, DegreeProgram::KINDS, "kind") }) if kind.present?
      relation = relation.where(degree_programs: { level: validated(level, DegreeProgram::LEVELS, "level") }) if level.present?
      relation = relation.where(degree_programs: { parent_program_id: parent_id(parent) }) if parent.present?
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
      relation = catalog_year.requirement_sets.joins(:degree_program).with_requirements
      key = program.to_s.strip.downcase
      relation.find_by(degree_programs: { slug: DegreeProgram.current_slug(key) }) ||
        relation.where("lower(requirement_sets.name) = ?", key).order(:id).first
    end

    # find, or UnknownProgramError.
    def find!(program, catalog_year:)
      find(program, catalog_year: catalog_year) || raise(UnknownProgramError.new(program, catalog_year))
    end

    private

    def parent_id(slug)
      id = DegreeProgram.where(slug: DegreeProgram.current_slug(slug.to_s.strip.downcase)).pick(:id)
      raise FilterError, "parent_program must be the slug of a program, such as computer-science-bs" if id.nil?

      id
    end

    def validated(value, allowed, name)
      values = Array(value).map { |v| v.to_s.strip.downcase }
      unknown = values - allowed.values
      raise FilterError, "#{name} must be one of #{allowed.values.join(', ')}" if unknown.any?

      values
    end
  end
end
