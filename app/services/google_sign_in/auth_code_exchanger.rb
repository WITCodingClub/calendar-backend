# frozen_string_literal: true

module GoogleSignIn
  # Trades a Google authorization code for an access token.
  #
  # The extension runs the PKCE flow but cannot finish it: Google requires a
  # client_secret at the token endpoint for a Web application client, and a
  # published extension is not a place to keep one: anyone can read it back out
  # of the package. So the extension hands over the code and this does the
  # exchange, with the secret staying here.
  #
  # PKCE still does its job across the two halves: the extension keeps the
  # verifier and sends it with the code, so a stolen code is useless without it.
  class AuthCodeExchanger
    READ_TIMEOUT = 5

    Result = Struct.new(:success, :access_token, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def self.exchange(code:, code_verifier:, redirect_uri:)
      new.exchange(code: code, code_verifier: code_verifier, redirect_uri: redirect_uri)
    end

    def exchange(code:, code_verifier:, redirect_uri:)
      return failure("missing code")         if code.blank?
      return failure("missing code_verifier") if code_verifier.blank?
      return failure("missing redirect_uri")  if redirect_uri.blank?

      client_id, client_secret = extension_client
      return failure("no OAuth client configured for the extension") if client_id.blank? || client_secret.blank?

      response = OauthCredentials::Http.post_form(GoogleCalendar::TOKEN_URL, {
        client_id:     client_id,
        client_secret: client_secret,
        code:          code,
        code_verifier: code_verifier,
        grant_type:    "authorization_code",
        redirect_uri:  redirect_uri
      }, read_timeout: READ_TIMEOUT)

      body = OauthCredentials::Http.parse(response.body)

      unless response.success?
        # Google's description names the actual problem (a spent code, a verifier
        # that does not match). Log it, but never hand it to the caller.
        return failure("google refused the exchange: #{body['error']} #{body['error_description']}".strip)
      end

      access_token = body["access_token"]
      return failure("google returned no access token") if access_token.blank?

      Result.new(success: true, access_token: access_token)
    rescue Faraday::Error => e
      failure("token exchange failed: #{e.message}")
    end

    private

    def failure(message)
      Result.new(success: false, error: message)
    end

    # The extension has its own OAuth client, because its redirect URIs are the
    # browser's (chromiumapp.org, extensions.allizom.org) rather than this site's.
    # Falls back to the web client so a single-client setup still works.
    def extension_client
      config = GoogleCalendar.config
      [ config[:extension_client_id] || config[:client_id], config[:extension_client_secret] || config[:client_secret] ]
    end
  end
end
