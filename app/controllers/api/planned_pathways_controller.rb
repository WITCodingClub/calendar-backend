# frozen_string_literal: true

module Api
  # Adds and removes a pathway a student plans, such as a 4+1 master's (#868).
  # Adding plans each program of the pathway that the student does not have
  # yet. Removing deletes only those planned rows. The MCP tool
  # update_my_planned_programs (with pathway) does the same.
  class PlannedPathwaysController < BaseController
    authenticate_with_token
    include Api::DegreePlanningFlag

    # POST /api/user/planned_pathways
    # Params: pathway (a pathway slug), catalog_year (optional, the newest
    # catalog year when blank).
    def create
      planned = AcademicProfiles::PlannedPrograms.new(current_user)
      pathway, programs = planned.build_pathway(pathway: params[:pathway], catalog_year: params[:catalog_year])
      programs.each { |program| authorize program, :create? }
      planned.save_pathway!(pathway, programs)

      # One timeline batch for all rows, so a pathway with many steps does
      # not query the requirement sets once for each row.
      timelines = AcademicProfiles::ProgramTimeline.for_programs(
        programs, admit_term_uid: current_user.academic_profile&.admit_term_uid
      )
      render json: { pathway:  ProgramPathwaySerializer.new(pathway).as_json,
                     programs: programs.map { |program| StudentProgramSerializer.new(program, timeline: timelines.fetch(program)).as_json } },
             status: :created
    rescue AcademicProfiles::InvalidProfileError => e
      render_error e.message, status: :unprocessable_content, code: e.code
    end

    # DELETE /api/user/planned_pathways/:id
    # id is the pathway slug.
    def destroy
      _pathway, programs = AcademicProfiles::PlannedPrograms.new(current_user).find_pathway(params[:id])
      if programs.nil?
        render_error "Planned pathway not found", status: :not_found
        return
      end

      programs.each { |program| authorize program, :destroy? }
      StudentProgram.transaction { programs.each(&:destroy!) }

      head :no_content
    end
  end
end
