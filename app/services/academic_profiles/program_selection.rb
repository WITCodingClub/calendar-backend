# frozen_string_literal: true

module AcademicProfiles
  # Which programs DegreeProgress checks, and with which plan of study: the
  # program argument, or each active (and with include_planned, planned)
  # program of the student with a catalog link. The plan is the plan
  # argument, or the plan the student picked (#867), or the standard plan.
  class ProgramSelection
    class UnknownPlanError < PlanningError; end

    # program, catalog_year, plan: the arguments of the request, as text or
    # nil.
    def initialize(user, program:, catalog_year:, plan:, include_planned:)
      @user = user
      @program = program
      @catalog_year = catalog_year
      @plan_name = plan
      @include_planned = include_planned
    end

    # Each requirement set to check, with its plan name and the student's
    # row (nil for the program argument). Raises
    # Catalog::ProgramQuery::FilterError for a program argument that the
    # catalog does not have.
    def entries
      if @program
        set = find_argument_set(Catalog::ProgramQuery.new)
        return [ [ set, argument_plan_name(set), nil ] ]
      end

      statuses = @include_planned ? %w[active planned] : %w[active]
      rows = @user.student_programs.where(status: statuses).where.not(degree_program_id: nil)
                  .includes(:catalog_year).order(:id).select { |row| row.catalog_year&.imported? }
      sets = RequirementSet.with_requirements.index_for(rows)

      rows.filter_map do |row|
        set = sets[[ row.degree_program_id, row.catalog_year_id ]]
        [ set, @plan_name || row.plan_name.presence, row ] if set
        # A planned row can have the same program as a later active row, for
        # example a minor the student then declared. Each keeps its entry.
      end.uniq { |set, _, row| [ set.id, row.status ] }
    end

    # The plan with this name, or the standard plan. A picked plan that a
    # later import renamed falls back to the standard plan. An unknown plan
    # argument raises UnknownPlanError.
    def plan(set, plan_name)
      picked = plan_name && set.plan_named(plan_name)
      return picked if picked

      if @plan_name
        raise UnknownPlanError, "No plan #{@plan_name}. #{set.name} has: #{set.program_plans.map(&:name).join(', ')}"
      end

      set.standard_plan
    end

    private

    def find_argument_set(query)
      year = @catalog_year ? query.catalog_year!(@catalog_year) : own_catalog_year(query)
      query.find!(@program, catalog_year: year)
    end

    # The catalog year of the student's own program with this slug, or the
    # newest catalog year.
    def own_catalog_year(query)
      own = own_program&.catalog_year
      own&.imported? ? own : query.catalog_year!(nil)
    end

    # The student's active row of the program argument, or nil.
    def own_program
      return @own_program if defined?(@own_program)

      @own_program = @user.student_programs.active.joins(:degree_program).includes(:catalog_year)
                          .find_by(degree_programs: { slug: DegreeProgram.current_slug(@program.to_s.strip.downcase) })
    end

    # The plan for the program argument: the plan argument, or the plan the
    # student picked for their own row of that program in the same catalog
    # year (#867).
    def argument_plan_name(set)
      return @plan_name if @plan_name

      own = own_program
      own.plan_name.presence if own && own.catalog_year_id == set.catalog_year_id
    end
  end
end
