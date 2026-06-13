# frozen_string_literal: true

module ApiResponseFormatter
  extend ActiveSupport::Concern

  def success_response(data:, message: nil, status: :ok)
    render json: {
      success: true,
      data: data,
      message: message
    }.compact, status: status
  end

  def error_response(error:, code:, status: :bad_request)
    render json: {
      success: false,
      error: error,
      code: code
    }, status: status
  end

  def auth_error(message = "Authentication required", code: "AUTH_MISSING")
    error_response(error: message, code: code, status: :unauthorized)
  end

  def validation_error(message, code: "VALIDATION_FAILED")
    error_response(error: message, code: code, status: :unprocessable_entity)
  end

  def not_found_error(message = "Resource not found")
    error_response(error: message, code: "NOT_FOUND", status: :not_found)
  end
end
