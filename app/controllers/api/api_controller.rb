# frozen_string_literal: true

module Api
  class ApiController < ActionController::API
    include Pundit::Authorization
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated
    include PublicIdLookupable

    self.gated_feature_key = :v1

    # Ensure all responses are JSON
    rescue_from StandardError, with: :render_internal_server_error
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :render_bad_request
    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

    private

    def render_forbidden(exception = nil)
      render json: { error: exception&.message || "You are not authorized to perform this action." }, status: :forbidden
    end

    def render_not_found(exception = nil)
      render json: { error: exception&.message || "Record not found" }, status: :not_found
    end

    def render_unprocessable_entity(exception)
      render json: { error: exception.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    def render_bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end

    def render_internal_server_error(exception)
      Rails.logger.error("API Error: #{exception.class} - #{exception.message}")
      Rails.logger.error(exception.backtrace&.first(10)&.join("\n"))

      if Rails.env.local?
        render json: { error: exception.message, backtrace: exception.backtrace&.first(5) }, status: :internal_server_error
      else
        render json: { error: "Internal server error" }, status: :internal_server_error
      end
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
