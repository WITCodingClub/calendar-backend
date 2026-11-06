# frozen_string_literal: true

module Api
  # The signed-in student's degree requirements next to the courses they took
  # or take (#799). The my_degree_progress MCP tool sends the same data. It is
  # a help for planning, not a degree audit.
  class DegreeProgressesController < BaseController
    authenticate_with_token

    # GET /api/user/degree_progress
    # Params (all optional): program (a slug), catalog_year and plan (with program).
    def show
      authorize current_user, :show?

      if params[:program].blank? && (params[:catalog_year].present? || params[:plan].present?)
        render_error "catalog_year and plan need program", status: :unprocessable_content
        return
      end

      render json: AcademicProfiles::DegreeProgress.new(
        current_user, program: params[:program], catalog_year: params[:catalog_year], plan: params[:plan]
      ).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError => e
      render_error e.message, status: :unprocessable_content, code: "no_program"
    rescue Catalog::FilterError => e
      render_error e.message, status: :unprocessable_content
    end
  end
end
