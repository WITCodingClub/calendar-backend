# frozen_string_literal: true

# app/controllers/concerns/api_response_formatter.rb
# Standardized API response formatting for consistency across all endpoints
module ApiResponseFormatter
  extend ActiveSupport::Concern

  # Success responses
  # @param data [Hash] The data payload to return
  # @param message [String, nil] Optional success message
  # @param status [Symbol] HTTP status code (default: :ok)
  def success_response(data:, message: nil, status: :ok)
    render json: {
      success: true,
      data: data,
      message: message
    }.compact, status: status
  end

  # Error responses
  # @param error [String] Error message
  # @param code [String] Error code from ApiErrorCodes
  # @param status [Symbol] HTTP status code (default: :bad_request)
  def error_response(error:, code:, status: :bad_request)
    render json: {
      success: false,
      error: error,
      code: code
    }, status: status
  end

  # Convenience method for authentication errors
  def auth_error(message = "Authentication required", code: ApiErrorCodes::AUTH_MISSING)
    error_response(error: message, code: code, status: :unauthorized)
  end

  # Convenience method for validation errors
  def validation_error(message, code: ApiErrorCodes::VALIDATION_FAILED)
    error_response(error: message, code: code, status: :unprocessable_entity)
  end

  # Convenience method for not found errors
  def not_found_error(message = "Resource not found")
    error_response(error: message, code: "NOT_FOUND", status: :not_found)
  end
end
