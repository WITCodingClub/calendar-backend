# frozen_string_literal: true

module Api
  class OnboardingsController < BaseController
    # POST /api/user/onboard
    #
    # Identity is the student's WIT Google account — the limited Workspace
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
    # See GoogleAuthCodeExchanger and GoogleTokenVerifier.
    def create
      preferred_name = params[:preferred_name]

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

      verification = GoogleTokenVerifier.verify_access_token(access_token)
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

      user = find_or_create_onboarding_user(wit_email, preferred_name)

      token = JsonWebTokenService.issue(user: user, source: "google_onboard", request: request)

      render json: { pub_id: user.public_id.delete_prefix("usr_"), jwt: token }, status: :ok
    rescue => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_error "Failed to onboard user", status: :internal_server_error
    end

    private

    # Returns [access_token, error]. A code takes precedence over a token, so a
    # client that sends both during a rollout gets the verified path.
    def resolve_google_access_token
      code = params[:google_auth_code].presence

      if code
        result = GoogleAuthCodeExchanger.exchange(
          code:          code,
          code_verifier: params[:code_verifier],
          redirect_uri:  params[:redirect_uri]
        )

        return [ nil, result.error ] unless result.success?

        return [ result.access_token, nil ]
      end

      [ params[:google_access_token].presence || params[:access_token].presence, nil ]
    end

    # Resolves the account for a Google-verified WIT email. Accounts have always
    # been keyed on the WIT address, so returning users match here — including
    # the ones created before onboarding verified anything.
    #
    # Matching only on the verified address is what closes the takeover hole: a
    # caller can reach exactly the account whose WIT identity they hold a Google
    # token for. Linked personal accounts (oauth_credentials) are deliberately
    # not matched, so a personal token can never resolve to a WIT identity.
    def find_or_create_onboarding_user(wit_email, preferred_name)
      existing = User.find_by(email: wit_email)
      return existing if existing

      first_name, last_name = preferred_name.to_s.strip.split(" ", 2)
      User.create!(
        email:      wit_email,
        first_name: first_name,
        last_name:  last_name,
        password:   SecureRandom.hex(24)
      )
    end
  end
end
