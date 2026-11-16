# frozen_string_literal: true

module Api
  # The signed-in student's degree requirements next to the courses they took
  # or take (#799). The my_degree_progress MCP tool sends the same data. It is
  # a help for planning, not a degree audit.
  class DegreeProgressesController < BaseController
    authenticate_with_token
    include DegreePlanningFlag

    # Params (all optional): program (a slug), catalog_year and plan (with
    # program), include_planned (true also checks the planned programs, as
    # the My programs dashboard page does).
    def show
      authorize current_user, :show?

      request = AcademicProfiles::DegreeProgressRequest.new(
        program: params[:program], catalog_year: params[:catalog_year], plan: params[:plan],
        include_planned: params[:include_planned].to_s == "true"
      )
      render json: request.call(current_user)
    rescue Catalog::FilterError => e
      render_error e.message, status: :unprocessable_content
    end
  end
end
