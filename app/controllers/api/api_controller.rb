# frozen_string_literal: true

module Api
  class ApiController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    self.gated_feature_key = :V1

    skip_before_action :verify_authenticity_token

  end
end
