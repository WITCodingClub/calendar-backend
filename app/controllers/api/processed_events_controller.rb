# frozen_string_literal: true

module Api
  # The signed-in user's own courses for a term, as the extension shows them.
  class ProcessedEventsController < BaseController
    include Api::TermLookup

    authenticate_with_token

    def processing_status
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      status_row = current_user.term_processing_statuses.find_by(term: term)
      enrolled = status_row.nil? && current_user.enrollments.exists?(term_id: term.id)
      render json: TermProcessingStatusSerializer.new(status_row, enrolled: enrolled).as_json, status: :ok
    end

    def index
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      render json: {
        classes:                Courses::EnrolledCourses.for(current_user, term),
        notifications_disabled: current_user.notifications_disabled?
      }, status: :ok
    end
  end
end
