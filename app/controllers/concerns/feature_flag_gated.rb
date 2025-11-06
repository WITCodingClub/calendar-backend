# frozen_string_literal: true

module FeatureFlagGated
  extend ActiveSupport::Concern

  included do
    class_attribute :gated_feature_key, default: :v1
    before_action :check_beta_access
  end

  private

  def check_beta_access
    feature_flag = FlipperFlags::MAP[gated_feature_key]
    unless feature_flag
      render json: { error: "Access denied. Unknown feature." }, status: :forbidden and return
    end

    return if Flipper.enabled?(feature_flag)
    return if current_user && Flipper.enabled?(feature_flag, current_user)

    render json: {
      error: "Access denied. This feature is currently in beta testing.",
      message: "Please contact support if you believe you should have access."
    }, status: :forbidden
  end
end
