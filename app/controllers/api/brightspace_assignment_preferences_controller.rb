# frozen_string_literal: true

module Api
  # The user's progress on an assignment and a personal deadline. These never
  # change the imported Brightspace data.
  class BrightspaceAssignmentPreferencesController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping

    before_action :set_assignment

    rescue_from Brightspace::SyncPayload::Invalid do |error|
      render json: { error: error.message }, status: :unprocessable_content
    end

    # GET /api/assignments/:assignment_id/preference
    def show
      authorize preference
      render_preference
    end

    # PUT/PATCH /api/assignments/:assignment_id/preference
    #
    # Changes only the fields in the body. A null due_at_override clears it.
    def update
      authorize preference
      preference.update!(preference_params)
      render_preference
    end

    private

    def set_assignment
      @assignment = find_brightspace_assignment!(params[:assignment_id])
    end

    def preference
      @preference ||= @assignment.preference || @assignment.build_preference(user: current_user)
    end

    def preference_params
      permitted = params.require(:assignment_preference).permit(:progress, :due_at_override)
      permitted[:due_at_override] = parse_override(permitted[:due_at_override]) if permitted.key?(:due_at_override)
      permitted
    end

    # A bad time would turn into nil and clear the override, so it is an error.
    def parse_override(value)
      return nil if value.nil?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise Brightspace::SyncPayload::Invalid, "due_at_override must be an ISO 8601 time"
    end

    def render_preference
      render json: {
        assignment_preference: Brightspace::AssignmentPreferenceSerializer.new(preference).as_json,
        version:               @assignment.course_offering.reload.version
      }
    end
  end
end
