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
  class ProgramsController < Dashboard::ApplicationController
    include Dashboard::DegreePlanningFlag

    def index
      authorize current_user, :show?

      @programs = StudentProgramsSerializer.new(current_user).as_json
      @progress = degree_progress
      query = Catalog::ProgramQuery.new
      @catalog_years = query.catalog_years.to_a
      @catalog_programs = @catalog_years.first ? query.call(catalog_year: @catalog_years.first).to_a : []
    end

    # The form to correct a value that LeopardWeb sent.
    def edit
      @program = find_program
      authorize @program, :update?
    end

    def update
      program = find_program
      authorize program, :update?

      AcademicProfiles::StudentCorrection.new(current_user).program!(program, program_params)
      redirect_to dashboard_programs_path, notice: "Program saved. WIT Calendar keeps your change until LeopardWeb shows a different program list."
    rescue AcademicProfiles::InvalidProfileError => e
      redirect_to edit_dashboard_program_path(program.public_id), alert: e.message
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

    def program_params
      params.expect(program: AcademicProfiles::StudentCorrection::PROGRAM_FIELDS)
    end

    def degree_progress
      AcademicProfiles::DegreeProgress.new(current_user, include_planned: true).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError
      nil
    end
  end
end
