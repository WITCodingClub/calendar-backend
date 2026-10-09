# frozen_string_literal: true

module Api
  # The signed-in user's own courses for a term, as the extension shows them.
  class ProcessedEventsController < BaseController
    include Api::TermLookup

    authenticate_with_token

    # GET /api/user/processed_events/status
    def processing_status
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      status_row = current_user.term_processing_statuses.find_by(term: term)
      enrolled = status_row.nil? && current_user.enrollments.exists?(term_id: term.id)
      render json: TermProcessingStatusSerializer.new(status_row, enrolled: enrolled).as_json, status: :ok
    end

    # GET /api/user/processed_events
    def index
      authorize current_user, :show?

      term = find_term_by_uid
      return if performed?

      enrollments = current_user
                    .enrollments
                    .where(term_id: term.id)
                    .includes(course: [
                      :faculties,
                      { meeting_times: [ :event_preference, { rooms: :building }, { course: :faculties } ] }
                    ])

      preference_resolver = PreferenceResolver.new(current_user)
      template_renderer   = CalendarTemplateRenderer.new

      structured_data = enrollments.map do |enrollment|
        EnrolledCourseSerializer.new(
          enrollment,
          term:               term,
          preference_resolver: preference_resolver,
          template_renderer:  template_renderer
        ).as_json
      end

      render json: {
        classes:                structured_data,
        notifications_disabled: current_user.notifications_disabled?
      }, status: :ok
    end
  end
end
