# frozen_string_literal: true

module Api
  # The flag gate of the programs and degree progress endpoints (#944). Include
  # it after authenticate_with_token, so the token check runs first. The
  # academic profile and course outcome endpoints have no gate: the extension
  # keeps sending LeopardWeb data while the flag is off.
  module DegreePlanningFlag
    extend ActiveSupport::Concern

    included do
      before_action :require_degree_planning
    end

    private

    def require_degree_planning
      return if Flipper.enabled?(FeatureFlags::DEGREE_PLANNING, current_user)

      render_error "Degree planning is not enabled", status: :not_found
    end
  end
end
