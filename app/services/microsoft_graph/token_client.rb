# frozen_string_literal: true

module MicrosoftGraph
  # Talks to the Microsoft identity platform for the calendar connection: the
  # authorize URL, the authorization code exchange, and token refresh.
  class TokenClient
    AUTHORITY    = "https://login.microsoftonline.com"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    Token = Struct.new(:access_token, :refresh_token, :expires_at, :claims, keyword_init: true)

    def self.code_challenge(code_verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    end

    def initialize(settings = MicrosoftGraph.config)
      @settings = settings
    end

    def authorize_url(state:, code_verifier:, redirect_uri:)
      query = {
        client_id:             settings[:client_id],
        response_type:         "code",
        response_mode:         "query",
        redirect_uri:          redirect_uri,
        scope:                 SCOPES.join(" "),
        state:                 state,
        code_challenge:        self.class.code_challenge(code_verifier),
        code_challenge_method: "S256",
        prompt:                "select_account"
      }

      "#{authority_url}/authorize?#{URI.encode_www_form(query)}"
    end

    def exchange_code(code:, code_verifier:, redirect_uri:)
      request_token(
        grant_type:    "authorization_code",
        code:          code,
        code_verifier: code_verifier,
        redirect_uri:  redirect_uri
      )
    end

    # Microsoft rotates refresh tokens, so the new one replaces the old one.
    #
    # invalid_grant means Microsoft will not take the refresh token again: the
    # person revoked access, an admin removed consent, or the token expired.
    # The credential is marked revoked, like a Google token that
    # RefreshOauthTokensJob cannot refresh, so the dashboard asks for a new
    # sign-in.
    # Microsoft gives a new refresh token with each refresh. Two refreshes of
    # one credential at the same time (a sync and RefreshOauthTokensJob) can
    # make the slower one use a token that is already replaced. Microsoft then
    # answers invalid_grant, and a good connection gets marked revoked. So the
    # row is locked, and a refresh that waited uses the token the other one got.
    def refresh!(credential)
      token_before_lock = credential.access_token

      # with_lock reads the row again, so the values below are the newest ones.
      credential.with_lock do
        raise AuthError, "credential has no refresh token" if credential.refresh_token.blank?
        next if credential.access_token != token_before_lock && !credential.token_expired?

        token = request_token(grant_type: "refresh_token", refresh_token: credential.refresh_token)
        credential.update!(
          access_token:     token.access_token,
          refresh_token:    token.refresh_token.presence || credential.refresh_token,
          token_expires_at: token.expires_at
        )
        token
      end
    rescue AuthError => e
      mark_revoked(credential) if e.body.is_a?(Hash) && e.body["error"] == "invalid_grant"
      raise
    end

    private

    attr_reader :settings

    def mark_revoked(credential)
      credential.update!(
        metadata: (credential.metadata || {}).merge(
          "token_revoked"     => true,
          "token_revoked_at"  => Time.current.iso8601,
          "revocation_reason" => "invalid_grant"
        )
      )
    end

    def authority_url
      "#{AUTHORITY}/#{settings[:tenant_id]}/oauth2/v2.0"
    end

    def request_token(**params)
      response = connection.post("#{authority_url}/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          params.merge(
            client_id:     settings[:client_id],
            client_secret: settings[:client_secret],
            scope:         SCOPES.join(" ")
          )
        )
      end

      body = parse(response.body)

      unless response.success?
        # The error code names the problem. The description can echo request
        # data, so it stays out of the message.
        raise AuthError.new("token request failed: #{body['error']}", status: response.status, body: body)
      end

      raise AuthError, "token response had no access token" if body["access_token"].blank?

      Token.new(
        access_token:  body["access_token"],
        refresh_token: body["refresh_token"],
        expires_at:    Time.current + body["expires_in"].to_i.seconds,
        claims:        id_token_claims(body["id_token"])
      )
    end

    # The id token comes straight from the token endpoint over TLS, so its
    # claims are read without a signature check (OpenID Connect Core 3.1.3.7).
    def id_token_claims(id_token)
      return {} if id_token.blank?

      JWT.decode(id_token, nil, false).first
    rescue JWT::DecodeError
      {}
    end

    def parse(body)
      return {} if body.blank?

      body.is_a?(String) ? JSON.parse(body) : body
    rescue JSON::ParserError
      {}
    end

    def connection
      @connection ||= Faraday.new(request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT })
    end
  end
end
