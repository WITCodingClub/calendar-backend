# frozen_string_literal: true

module Api
  # The signed-in student's plan of study as a prerequisite graph, by semester
  # (#449), and the courses before and after one focus course (#448). The
  # dashboard page /dashboard/curriculum shows the same data.
  class CurriculumGraphsController < BaseController
    authenticate_with_token

    # GET /api/user/curriculum_graph
    # Params (all optional): program (a slug), catalog_year and plan (with
    # program), focus (a course code such as "COMP 2350" or "COMP2350").
    def show
      authorize current_user, :show?

      if params[:program].blank? && (params[:catalog_year].present? || params[:plan].present?)
        render_error "catalog_year and plan need program", status: :unprocessable_content
        return
      end

      render json: AcademicProfiles::CurriculumGraph.new(
        current_user, program: params[:program], catalog_year: params[:catalog_year], plan: params[:plan],
                      focus: params[:focus]
      ).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError => e
      render_error e.message, status: :unprocessable_content, code: "no_program"
    rescue Catalog::FilterError => e
      render_error e.message, status: :unprocessable_content
    end
  end
end
