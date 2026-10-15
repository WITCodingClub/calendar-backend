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
    before_action :sync_client_scopes, only: %i[new create]
    before_action :normalize_scope, only: %i[new create destroy]
    before_action :drop_unapproved_scopes, only: :create

    helper_method :consent_scopes

    private

    def consent_scopes
      @consent_scopes ||= Oauth::ConsentScopes.new(params[:scope], previous: previous_token_scopes)
    end

    # A client registered before the scopes were split lists only "read".
    # Doorkeeper refuses a request for a scope that the client does not list,
    # so give each registered client the current list.
    def sync_client_scopes
      application = Doorkeeper::Application.find_by(uid: params[:client_id].to_s)
      return unless application&.dynamic?

      scopes = McpTools::Scopes::NAMES.join(" ")
      application.update!(scopes: scopes) unless application.scopes.to_s == scopes
    end

    # The legacy read scope becomes the read scopes it stands for, so the
    # consent page shows a box for each.
    def normalize_scope
      params[:scope] = consent_scopes.requested_scope if params[:scope].present?
    end

    # Doorkeeper grants the scope string of the form. Keep only the scopes
    # whose box the student checked.
    def drop_unapproved_scopes
      params[:scope] = consent_scopes.granted_scope(params[:scopes])
    end

    def previous_token_scopes
      application = Doorkeeper::Application.find_by(uid: params[:client_id].to_s)
      return if application.nil? || current_resource_owner.nil?

      Doorkeeper::AccessToken.where(application: application, resource_owner_id: current_resource_owner.id, revoked_at: nil)
                             .order(created_at: :desc).pick(:scopes)
    end

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
