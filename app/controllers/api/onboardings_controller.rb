# frozen_string_literal: true

module Api
  class OnboardingsController < BaseController
    # Identity is the student's WIT Google account: the limited Workspace
    # account the school provisions on the wit.edu domain. We verify it with
    # Google and key the account to that verified @wit.edu address, so it proves
    # two things at once: the caller controls the Google identity, and only WIT
    # could have issued it. A personal Google account is linked afterwards, for
    # calendar sync only (POST /api/user/google_calendar), and never becomes the identity.
    #
    # The extension runs the PKCE flow and sends the authorization code, because
    # Google wants a client_secret at the token endpoint and a published
    # extension cannot keep one. We finish the exchange here. A caller that
    # already holds an access token may send that instead.
    # See GoogleSignIn::AuthCodeExchanger and GoogleSignIn::TokenVerifier.
    def create
      access_token, exchange_error = resolve_google_access_token

      if exchange_error
        Rails.logger.warn("Onboard code exchange failed: #{exchange_error}")
        render_error "Could not complete Google sign-in", status: :unauthorized
        return
      end

      if access_token.blank?
        render_error "google_auth_code or google_access_token is required", status: :bad_request
        return
      end

      verification = GoogleSignIn::TokenVerifier.verify_access_token(access_token)
      unless verification.success?
        Rails.logger.warn("Onboard token verification failed: #{verification.error}")
        render_error "Invalid Google token", status: :unauthorized
        return
      end

      unless verification.email_verified?
        render_error "Google has not verified this email address", status: :forbidden
        return
      end

      wit_email = verification.email

      unless User.wit_email?(wit_email)
        render_error "Sign in with your @#{User::WIT_EMAIL_DOMAIN} Google account. " \
                     "You can connect a personal Google account for calendar sync afterwards.",
                     status: :forbidden,
                     code: "WIT_ACCOUNT_REQUIRED"
        return
      end

      # Matching only on the verified WIT address closes the takeover hole: a
      # caller reaches exactly the account whose WIT identity they hold a
      # Google token for. Linked personal accounts (oauth_credentials) are not
      # matched, so a personal token never resolves to a WIT identity.
      first_name, last_name = params[:preferred_name].to_s.strip.split(" ", 2)
      user = User.find_or_provision_for_sign_in!(email: wit_email, first_name: first_name, last_name: last_name)

      token = JsonWebTokenService.issue(user: user, source: "google_onboard", request: request)

      render json: SessionTokenSerializer.new(user, token).as_json, status: :ok
    end

    private

    # Returns [access_token, error]. A code takes precedence over a token, so a
    # client that sends both during a rollout gets the verified path.
    def resolve_google_access_token
      code = params[:google_auth_code].presence

      if code
        result = GoogleSignIn::AuthCodeExchanger.exchange(
          code:          code,
          code_verifier: params[:code_verifier],
          redirect_uri:  params[:redirect_uri]
        )

        return [ nil, result.error ] unless result.success?

        return [ result.access_token, nil ]
      end

      [ params[:google_access_token].presence || params[:access_token].presence, nil ]
    end
  end
end
