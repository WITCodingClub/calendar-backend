# frozen_string_literal: true

module Api
  # The final exams of the signed-in user's courses in one term. The my_finals
  # MCP tool sends the same data. schedule_published is false until a finals
  # schedule finishes its import, so a client can tell "not out yet" from "no
  # finals".
  class FinalsController < BaseController
    include Api::TermLookup

    authenticate_with_token

    # GET /api/user/finals?term_uid=202610
    def index
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      exams = Courses::FinalExamsQuery.new(current_user, term).call
      render json: {
        term_uid:           term.uid,
        schedule_published: term.finals_published?,
        finals:             EnrolledFinalExamSerializer.render_collection(exams)
      }
    end
  end
end
