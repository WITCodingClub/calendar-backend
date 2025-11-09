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

    # Transform reminder settings to use "notification" instead of "popup"
    # Google Calendar uses "popup", but we alias it to "notification" in our API
    def transform_reminder_settings(reminder_settings)
      return nil if reminder_settings.nil?
      return [] if reminder_settings.empty?

      reminder_settings.map do |reminder|
        reminder = reminder.deep_symbolize_keys if reminder.is_a?(Hash)
        next reminder unless reminder.is_a?(Hash)

        reminder[:method] = "notification" if reminder[:method] == "popup"
        reminder.transform_keys(&:to_s) # Ensure string keys for JSON
      end
    end

  end
end
