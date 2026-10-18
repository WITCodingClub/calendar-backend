# frozen_string_literal: true

module Oauth
  # Dynamic client registration (RFC 7591). MCP clients such as claude.ai and
  # ChatGPT register here before they send the user to the consent page.
  # Oauth::ClientRegistration holds the rules.
  class RegistrationsController < ActionController::API
    def create
      application = Oauth::ClientRegistration.new(registration_params).call
      Yabeda.calendar.oauth_clients_registered_total.increment({})

      render status: :created, json: {
        client_id:                  application.uid,
        client_id_issued_at:        application.created_at.to_i,
        client_name:                application.name,
        redirect_uris:              application.redirect_uri.split,
        grant_types:                %w[authorization_code refresh_token],
        response_types:             %w[code],
        token_endpoint_auth_method: "none",
        scope:                      application.scopes.to_s
      }
    rescue Oauth::InvalidClientMetadataError => e
      render status: :bad_request, json: { error: e.code, error_description: e.message }
    rescue ActiveRecord::RecordInvalid => e
      render status: :bad_request, json: { error: "invalid_client_metadata", error_description: e.record.errors.full_messages.to_sentence }
    end

    private

    # RFC 7591 sends JSON. A body that is not a JSON object has no metadata.
    def registration_params
      body = request.request_parameters
      body.is_a?(Hash) ? body.slice(*%w[client_name redirect_uris token_endpoint_auth_method grant_types response_types]) : {}
    end
  end
end
