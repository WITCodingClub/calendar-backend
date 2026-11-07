# frozen_string_literal: true

module Admin
  # Browse the programs of the degree requirements import (#864): each
  # program, its requirement set for each catalog year, its plans of study
  # semester by semester, and its elective lists. The :id of a route is the
  # program slug.
  class DegreeProgramsController < Admin::ApplicationController
    def index
      authorize DegreeProgram

      programs = DegreeProgram.includes(:parent_program).order(:name)
      if params[:search].present?
        pattern = "%#{DegreeProgram.sanitize_sql_like(params[:search].to_s.strip)}%"
        programs = programs.where("degree_programs.name ILIKE :pattern OR degree_programs.slug ILIKE :pattern", pattern: pattern)
      end
      programs = programs.where(kind: params[:kind]) if DegreeProgram.kinds.key?(params[:kind])
      @degree_programs = programs.page(params[:page]).per(50)
      @start_years = RequirementSet.joins(:catalog_year)
                                   .where(degree_program_id: @degree_programs.map(&:id))
                                   .pluck(:degree_program_id, "catalog_years.start_year")
                                   .group_by(&:first)
                                   .transform_values { |pairs| pairs.map(&:last).sort }
    end

    def show
      @degree_program = DegreeProgram.includes(:parent_program, :concentrations).find_by!(slug: DegreeProgram.current_slug(params[:id]))
      authorize @degree_program

      @requirement_sets = @degree_program.requirement_sets.includes(:catalog_year).sort_by { |set| -set.catalog_year.start_year }
      chosen = @requirement_sets.find { |set| set.catalog_year.start_year.to_s == params[:year] } || @requirement_sets.first
      return if chosen.nil?

      @requirement_set = RequirementSet.includes(:catalog_year, degree_program: :parent_program,
                                                 program_plans: { items: :elective_group },
                                                 elective_groups: %i[courses program_plan])
                                       .find(chosen.id)
      @program = Catalog::ProgramSerializer.new(@requirement_set).as_json
    end
  end
end
