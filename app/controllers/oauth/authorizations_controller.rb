# frozen_string_literal: true

module Oauth
  # The consent page of the OAuth server: GET /api/oauth/authorize shows it, POST
  # approves, DELETE denies. Doorkeeper does the OAuth work. This subclass adds
  # the app layout, the RFC 8707 resource check, and a wider form-action for
  # the redirect back to the client.
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout "sessions"

    # After the user approves, the browser goes to the client's redirect URI.
    # Browsers check form-action against that redirect, and the URI belongs
    # to the client, so this page allows any HTTPS host and the loopback
    # addresses that Oauth::RedirectUris accepts.
    content_security_policy do |policy|
      policy.form_action :self, :https, "http://localhost:*", "http://127.0.0.1:*"
    end

    before_action :load_client_metadata_document
    before_action :check_resource, only: %i[new create]

    private

    # A client_id that is an HTTPS URL names a client ID metadata document.
    # Fetch it (or the kept copy) before Doorkeeper looks the client up.
    # An error renders here, never redirects: the redirect URI is not
    # trusted until the document is.
    def load_client_metadata_document
      return unless Oauth::ClientMetadataDocument.client_id?(params[:client_id])

      Oauth::ClientMetadataDocument.new(params[:client_id]).application
    rescue Oauth::InvalidClientMetadataError => e
      render :unavailable, status: :bad_request, locals: { message: "This app's details could not be checked: #{e.message}." }
    end

    # RFC 8707: a client names the server it wants a token for. This server
    # issues tokens for the MCP endpoint only, so any other resource is
    # refused before the user sees the consent page.
    def check_resource
      resource = params[:resource]
      return if resource.blank?
      return if resource.to_s.chomp("/") == Oauth::Metadata.new(host: request.host, port: request.port, protocol: request.protocol).resource

      render :unavailable, status: :bad_request, locals: { message: "This server cannot issue a token for #{resource}." }
    end
  end
end
