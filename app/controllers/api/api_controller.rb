# frozen_string_literal: true

module Api
  class ApiController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    skip_before_action :verify_authenticity_token
  end
end