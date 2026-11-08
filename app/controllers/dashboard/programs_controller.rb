# frozen_string_literal: true

module Dashboard
  # My programs (#867): the student's programs from LeopardWeb with the plan
  # of each against real terms, the programs they plan ("what if"), and the
  # ended programs. A help for planning, not a degree audit: the official
  # audit is Stellic.
  #
  # The page shows the hashes of GET /api/user/programs
  # (StudentProgramsSerializer) and GET /api/user/degree_progress with
  # include_planned (AcademicProfiles::DegreeProgress), so it shows the same
  # data as the API.
  #
  # The programs come only from LeopardWeb, through the extension. A student
  # cannot change them here.
  class ProgramsController < Dashboard::ApplicationController
    include Dashboard::DegreePlanningFlag

    def index
      authorize current_user, :show?

      @programs = StudentProgramsSerializer.new(current_user).as_json
      @progress = degree_progress
      @next_term = @progress && AcademicProfiles::NextTermCourses.new(current_user, programs: @programs, progress: @progress).call
      query = Catalog::ProgramQuery.new
      @catalog_years = query.catalog_years.to_a
      @catalog_programs = @catalog_years.first ? query.call(catalog_year: @catalog_years.first).to_a : []
      @pathways = ProgramPathway.active.order(:name).to_a
    end

    # Picks the plan of study of an active or a planned program, or confirms
    # the assumed one.
    def plan
      program = find_program
      authorize program, :update_plan?

      chosen = AcademicProfiles::ProgramTimeline.for_program(program).plan_named(params[:plan])
      if chosen
        program.update!(plan_name: chosen.name)
        redirect_to dashboard_programs_path, notice: "Plan saved: #{chosen.name}."
      else
        redirect_to dashboard_programs_path, alert: "Pick a plan of study from the list."
      end
    end

    private

    # The student's own row. Another student's id finds nothing, and the
    # policy refuses an admin's request for another student's row.
    def find_program
      policy_scope(StudentProgram).find_by_public_id!(params[:id])
    end

    def degree_progress
      AcademicProfiles::DegreeProgress.new(current_user, include_planned: true).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError
      nil
    end
  end
end
