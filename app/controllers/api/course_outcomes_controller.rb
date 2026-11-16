# frozen_string_literal: true

module Api
  # The outcome of each finished course, from the LeopardWeb Student Grades
  # page (#529). The extension never sends the letter grade.
  class CourseOutcomesController < BaseController
    authenticate_with_token

    def update
      authorize current_user, :update?

      terms = params.to_unsafe_h[:terms]
      results = CourseOutcomes::Recorder.new(current_user, terms).call

      render json: { terms: results.map(&:as_json) }
    end
  end
end
