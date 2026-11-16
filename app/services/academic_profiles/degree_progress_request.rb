# frozen_string_literal: true

module AcademicProfiles
  # The arguments of GET /api/user/degree_progress and of the MCP tool
  # my_degree_progress, checked once for both (DegreeProgress).
  class DegreeProgressRequest
    class InvalidArgumentsError < PlanningError; end

    # Raises PlanningError when catalog_year or plan comes without program.
    def initialize(program:, catalog_year:, plan:, include_planned: false)
      if program.blank? && (catalog_year.present? || plan.present?)
        raise InvalidArgumentsError, "catalog_year and plan need program"
      end

      @arguments = { program: program, catalog_year: catalog_year, plan: plan, include_planned: include_planned }
    end

    # Raises PlanningError, or Catalog::ProgramQuery::FilterError for a
    # program or catalog year that the catalog does not have.
    def call(user) = DegreeProgress.new(user, **@arguments).call
  end
end
