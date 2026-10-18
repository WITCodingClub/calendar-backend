# frozen_string_literal: true

module Oauth
  # Client ID metadata documents (draft-ietf-oauth-client-id-metadata-document),
  # the client registration that the MCP spec prefers.
  #
  # The client_id is an HTTPS URL. The document at that URL names the client
  # and its redirect URIs, and its own client_id must be that URL. Only the
  # owner of the domain can publish it, so the consent page can name the
  # domain the app comes from.
  #
  # The first authorization request fetches the document and keeps it as a
  # Doorkeeper::Application with the URL as its uid. The token endpoint then
  # finds the client like any other. A copy older than REFRESH_AFTER is
  # fetched again, so a client can change its redirect URIs.
  class ClientMetadataDocument
    REFRESH_AFTER = 1.hour
    MAX_URL_LENGTH = RedirectUris::MAX_LENGTH

    def self.client_id?(client_id)
      client_id.to_s.start_with?("https://")
    end

    def initialize(client_id, client: MetadataDocumentClient.new)
      @client_id = client_id.to_s
      @client    = client
    end

    # @return [Doorkeeper::Application]
    # @raise [InvalidClientMetadataError]
    def application
      existing = Doorkeeper::Application.find_by(uid: @client_id)
      return existing if existing && existing.updated_at > REFRESH_AFTER.ago

      attributes = ClientRegistration.new(document).attributes
      app = existing || Doorkeeper::Application.new(uid: @client_id)
      app.assign_attributes(attributes)
      app.touch if app.persisted? && !app.changed?
      app.save!
      app
    rescue ActiveRecord::RecordNotUnique
      # Two first requests for the same client at once. The other one won.
      Doorkeeper::Application.find_by!(uid: @client_id)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:uid, :taken)

      Doorkeeper::Application.find_by!(uid: @client_id)
    end

    private

    def document
      document = @client.fetch(uri)
      return document if document["client_id"] == @client_id

      raise InvalidClientMetadataError.new("invalid_client", "the client metadata document names a different client_id")
    rescue MetadataDocumentClient::FetchError => e
      raise InvalidClientMetadataError.new("invalid_client", e.message)
    end

    # The draft asks for an https URL with a path, and no fragment, user info,
    # or dot segments.
    def uri
      raise invalid_client_id if @client_id.length > MAX_URL_LENGTH

      uri = URI.parse(@client_id)
      valid = uri.is_a?(URI::HTTPS) && uri.host.present? && uri.path.present? && uri.path != "/" &&
              uri.fragment.nil? && uri.userinfo.nil? && uri.path.split("/").none? { |segment| segment.in?(%w[. ..]) }
      raise invalid_client_id unless valid

      uri
    rescue URI::InvalidURIError
      raise invalid_client_id
    end

    def invalid_client_id
      InvalidClientMetadataError.new("invalid_client", "the client id is not a valid metadata document URL")
    end
  end
end
