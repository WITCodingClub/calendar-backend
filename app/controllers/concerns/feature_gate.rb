# frozen_string_literal: true

# Answers 404 while a Flipper flag is off for the signed-in user, so the routes
# of a feature that is not out yet look absent. An API controller answers with
# the JSON error format (Api::BaseController overrides feature_off), a page
# controller with an empty 404. A halted before_action skips
# verify_authorized, so the 404 needs no authorize. Declare the gate after
# authenticate_with_token, so the token check runs first.
module FeatureGate
  extend ActiveSupport::Concern

  class_methods do
    def require_feature(flag, message, **)
      before_action(**) { feature_off(message) unless Flipper.enabled?(flag, current_user) }
    end
  end

  private

  def feature_off(_message)
    head :not_found
  end
end
