# frozen_string_literal: true

module Api
  # The courses the plan of study puts in the term the signed-in student
  # registers for next (#449). It is a help for planning, not a degree audit.
  class NextTermCoursesController < BaseController
    authenticate_with_token
    include DegreePlanningFlag

    # Params (optional): term, a Banner code (202720) or a label ("Spring
    # 2027"). assume: course codes to count as passed before the term,
    # separated by commas. assume_plans=true: also count the courses of the
    # saved registration plans before the term (#996). include=candidates:
    # add the candidates of each elective slot and choice (#993); it also
    # takes a list separated by commas.
    def show
      authorize current_user, :show?

      request = AcademicProfiles::NextTermRequest.new(term: params[:term], assume: params[:assume],
                                                      assume_plans: params[:assume_plans].to_s == "true",
                                                      include_candidates: candidates_requested?)
      render json: request.call(current_user)
    end

    private

    def candidates_requested?
      Array.wrap(params[:include]).flat_map { |item| item.is_a?(String) ? item.split(",") : [] }.map(&:strip).include?("candidates")
    end
  end
end
