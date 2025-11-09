# frozen_string_literal: true

module Api
  class ApiController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    self.gated_feature_key = :v1

    skip_before_action :verify_authenticity_token

    # Handle Pundit authorization errors with JSON response
    rescue_from Pundit::NotAuthorizedError, with: :pundit_not_authorized

    private

    def pundit_not_authorized
      render json: { error: "You are not authorized to perform this action." }, status: :forbidden
    end

  end
end
