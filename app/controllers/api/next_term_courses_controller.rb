# frozen_string_literal: true

module Api
  # The courses the plan of study puts in the term the signed-in student
  # registers for next (#449). It is a help for planning, not a degree audit.
  class NextTermCoursesController < BaseController
    authenticate_with_token
    include Api::DegreePlanningFlag

    # GET /api/user/next_term_courses
    # Params (optional): term, a Banner code (202720) or a label
    # ("Spring 2027"). Without it, the next fall or spring term.
    def show
      authorize current_user, :show?

      term_uid = nil
      if params[:term].present?
        term_uid = AcademicProfiles::TermCode.parse(params[:term].to_s)
        return render_error("term must be a Banner term code or a label such as Spring 2027", status: :unprocessable_content) if term_uid.nil?
      end

      render json: AcademicProfiles::NextTermCourses.new(current_user, term_uid: term_uid).call
    rescue AcademicProfiles::DegreeProgress::NoProgramError => e
      render_error e.message, status: :unprocessable_content, code: "no_program"
    end
  end
end
