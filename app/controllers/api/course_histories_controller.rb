# frozen_string_literal: true

module Api
  # Every term the signed-in user has processed, with the courses in each
  # term. The my_course_history MCP tool sends the same data.
  class CourseHistoriesController < BaseController
    authenticate_with_token

    # GET /api/user/course_history
    def show
      authorize current_user, :show?

      render json: Courses::HistoryBuilder.new(current_user).build
    end
  end
end
