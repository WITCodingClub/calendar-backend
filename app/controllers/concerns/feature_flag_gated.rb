# frozen_string_literal: true

module FeatureFlagGated
  extend ActiveSupport::Concern

  included do
    # Note: Controllers can override this by using skip_before_action :check_beta_access, only: [:action_name]
    before_action :check_beta_access
  end

  private

  def check_beta_access
    feature_flag = :"2025_10_04_beta_test"

    # Check if feature is globally enabled
    return if Flipper.enabled?(feature_flag)

    # Check if feature is enabled for the current user
    if current_user && Flipper.enabled?(feature_flag, current_user)
      return
    end

    render json: {
      error: "Access denied. This feature is currently in beta testing.",
      message: "Please contact support if you believe you should have access."
    }, status: :forbidden
  end
end
