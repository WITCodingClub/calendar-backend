# frozen_string_literal: true

module Api
  # The final exams of the signed-in user's courses in one term. The my_finals
  # MCP tool sends the same data.
  class FinalsController < BaseController
    include Api::TermLookup

    authenticate_with_token

    # GET /api/user/finals?term_uid=202610
    def index
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      exams = Courses::FinalExamsQuery.new(current_user, term).call
      render json: { term_uid: term.uid, finals: exams.map { |exam| EnrolledFinalExamSerializer.new(exam).as_json } }
    end
  end
end
