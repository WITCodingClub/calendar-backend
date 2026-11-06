# frozen_string_literal: true

module Api
  # Adds and removes the programs a student plans, such as a minor they think
  # about taking (#868). A LeopardWeb program never changes here. The MCP tool
  # update_my_planned_programs does the same.
  class PlannedProgramsController < BaseController
    authenticate_with_token

    # POST /api/user/planned_programs
    # Params: program (a slug from GET /api/v1/catalog/programs), catalog_year
    # (optional, the newest catalog year when blank).
    def create
      planned = AcademicProfiles::PlannedPrograms.new(current_user)
      program = planned.build(program: params[:program], catalog_year: params[:catalog_year])
      authorize program, :create?
      planned.save!(program)

      render json: StudentProgramSerializer.new(program).as_json, status: :created
    rescue AcademicProfiles::InvalidProfileError => e
      render_error e.message, status: :unprocessable_content, code: e.code
    end

    # DELETE /api/user/planned_programs/:id
    # id is the public id of the planned row, or the slug of its program.
    def destroy
      program = AcademicProfiles::PlannedPrograms.new(current_user).find(params[:id])
      if program.nil?
        render_error "Planned program not found", status: :not_found
        return
      end

      authorize program, :destroy?
      program.destroy!

      head :no_content
    end
  end
end
