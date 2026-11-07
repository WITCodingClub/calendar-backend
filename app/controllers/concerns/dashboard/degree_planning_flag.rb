# frozen_string_literal: true

module Dashboard
  # The flag gate of the My programs pages (#944). While the flag is off for
  # the user, every action answers 404 and the nav hides the Programs item.
  module DegreePlanningFlag
    extend ActiveSupport::Concern

    included do
      before_action :require_degree_planning
    end

    private

    def require_degree_planning
      head :not_found unless Flipper.enabled?(FeatureFlags::DEGREE_PLANNING, current_user)
    end
  end
end
