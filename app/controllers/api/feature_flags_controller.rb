# frozen_string_literal: true

module Api
  class FeatureFlagsController < BaseController
    authenticate_with_token

    # GET /api/user/feature_flags
    def index
      authorize current_user, :show?
      flags = {}
      FlipperFlags::ALL_FLAGS.each do |flag_name|
        flipper_key = FlipperFlags::MAP[flag_name]
        next if flipper_key.nil?
        flags[flag_name] = Flipper[flipper_key].enabled?(current_user)
      end
      render json: { feature_flags: flags }, status: :ok
    end

    # GET /api/user/flag_enabled (legacy, see config/routes/api_legacy.rb)
    def show
      feature_name = params[:flag_name]
      if feature_name.blank?
        render_error "flag_name is required", status: :bad_request
        return
      end

      feature_sym = feature_name.to_sym
      unless FlipperFlags::ALL_FLAGS.include?(feature_sym)
        render_error "Unknown feature flag", status: :not_found, feature_name: feature_name
        return
      end

      flipper_key = FlipperFlags::MAP[feature_sym]
      if flipper_key.nil?
        render_error "Invalid flag mapping", status: :unprocessable_content, feature_name: feature_name
        return
      end

      feature = Flipper[flipper_key]
      render json: { feature_name: feature_name, is_enabled: feature.enabled?(current_user) }, status: :ok
    end
  end
end
