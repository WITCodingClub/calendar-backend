# frozen_string_literal: true

module Api
  # The signed-in student's programs (#868): active, planned, and ended. The
  # my_programs MCP tool sends the same data.
  class StudentProgramsController < BaseController
    authenticate_with_token
    include Api::DegreePlanningFlag

    # GET /api/user/programs
    def index
      authorize current_user, :show?

      render json: StudentProgramsSerializer.new(current_user).as_json
    end
  end
end
