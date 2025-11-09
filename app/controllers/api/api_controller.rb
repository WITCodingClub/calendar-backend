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

    # Normalize color to WITCC hex format for API responses
    # Handles: integers (1-11), WITCC hex (already correct), Google event hex (convert to WITCC)
    # @param color_id_or_hex [Integer, String, nil] Color ID or hex string
    # @return [String, nil] WITCC hex color or nil
    def normalize_color_to_witcc_hex(color_id_or_hex)
      return nil if color_id_or_hex.blank?

      # If it's an integer, convert to WITCC hex
      if color_id_or_hex.is_a?(Integer)
        return GoogleColors.to_witcc_hex(color_id_or_hex)
      end

      # If it's a hex string, check if it's already a WITCC color
      if color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
        normalized_hex = color_id_or_hex.downcase

        # Check if it's already a WITCC color (key in WITCC_MAP)
        return normalized_hex if GoogleColors::WITCC_MAP.key?(normalized_hex)

        # Otherwise try to convert from Google event hex to WITCC hex
        return GoogleColors.to_witcc_hex(color_id_or_hex)
      end

      nil
    end

  end
end
