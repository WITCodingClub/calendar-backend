# frozen_string_literal: true

# The flag gate of the programs and degree progress endpoints and pages (#944).
# The academic profile and course outcome endpoints have no gate: the
# extension keeps sending LeopardWeb data while the flag is off.
module DegreePlanningFlag
  extend ActiveSupport::Concern

  included do
    require_feature FeatureFlags::DEGREE_PLANNING, "Degree planning is not enabled"
  end
end
