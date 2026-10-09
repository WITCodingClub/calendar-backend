# frozen_string_literal: true

module Api
  class FeatureFlagsController < BaseController
    authenticate_with_token

    # GET /api/user/feature_flags
    def index
      authorize current_user, :show?
      flags = {}
      FeatureFlags::ALL_FLAGS.each do |flag_name|
        flipper_key = FeatureFlags::MAP[flag_name]
        next if flipper_key.nil?
        flags[flag_name] = Flipper[flipper_key].enabled?(current_user)
      end
      render json: { feature_flags: flags }, status: :ok
    end
  end
end
