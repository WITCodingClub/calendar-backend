# frozen_string_literal: true

module Api
  class ApiController < ActionController::API
    include Pundit::Authorization
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated
    include PublicIdLookupable
    include PreferenceSerializable

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
      render json: { error: exception.record.errors.full_messages.join(", ") }, status: :unprocessable_content
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

  end
end
