# frozen_string_literal: true

module Api
  class CourseRecommendationsController < ApiController
    # GET /api/users/me/course_recommendations?term_uid=202430
    def index
      authorize current_user, :show?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      result = CourseRecommendationService.call(user: current_user, term: term)
      render json: result, status: :ok
    end

  end
end
