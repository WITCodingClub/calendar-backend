# frozen_string_literal: true

module Api
  # One error format for the whole API:
  #
  #   { "error": "Term not found", "code": "NOT_FOUND" }
  #
  # A client branches on code, not on the message. An action can pass its own
  # code and extra fields: render_error "...", status: :forbidden,
  # code: "NOT_FRIENDS". Without a code, the code comes from the status.
  module ErrorRendering
    extend ActiveSupport::Concern

    # Codes that differ from the HTTP reason phrase. Every other status uses its
    # reason phrase: 404 Not Found gives NOT_FOUND.
    CODES_BY_STATUS = {
      422 => "VALIDATION_FAILED",
      429 => "RATE_LIMITED",
      500 => "INTERNAL_ERROR"
    }.freeze

    included do
      # Declared first. rescue_from tries the last handler first, so the
      # specific handlers below win over this one.
      rescue_from StandardError, with: :render_internal_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
      rescue_from ActionController::BadRequest, ActionController::ParameterMissing, with: :render_bad_request
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
    end

    def self.code_for(status)
      number = Rack::Utils.status_code(status)
      CODES_BY_STATUS.fetch(number) { Rack::Utils::HTTP_STATUS_CODES.fetch(number).upcase.tr(" ", "_") }
    end

    private

    def render_error(message, status:, code: nil, **extra)
      render json: { error: message, code: code || ErrorRendering.code_for(status) }.merge(extra), status: status
    end

    def render_forbidden(exception = nil)
      render_error exception&.message.presence || "You are not authorized to perform this action.", status: :forbidden
    end

    def render_not_found(exception = nil)
      render_error exception&.message || "Not found", status: :not_found
    end

    def render_record_invalid(exception)
      render_error exception.record.errors.full_messages.join(", "), status: :unprocessable_content
    end

    def render_bad_request(exception)
      render_error exception.message, status: :bad_request
    end

    # The message stays generic, so the body shows no internals. The details
    # go to the log and to the error reporter. Only development adds the cause
    # to the body.
    def render_internal_error(exception)
      Rails.logger.error("API error: #{exception.class} - #{exception.message}")
      Rails.logger.error(exception.backtrace&.first(10)&.join("\n"))
      Rails.error.report(exception)

      if Rails.env.development?
        render_error exception.message, status: :internal_server_error, backtrace: exception.backtrace&.first(5)
      else
        render_error "Internal server error", status: :internal_server_error
      end
    end
  end
end
