# frozen_string_literal: true

module Api
  # Passkeys are a second way into an account that Google already vouched for.
  # Onboarding still runs through the WIT Google account, so a passkey never
  # creates an account and never widens who can hold one. It only saves a
  # student from repeating the Google flow on every new device.
  #
  # Both ceremonies are two calls: ask for options (which issues a challenge),
  # then send back what the authenticator produced. The API keeps no session, so
  # the challenge travels as an opaque handle and is consumed on the second call.
  #
  # The ceremony is meant to run on a page of this site, not inside a browser
  # extension: the credential is bound to WEBAUTHN_RP_ID either way, and keeping
  # the prompt on the site keeps the reported origin stable across browsers and
  # builds. See config/initializers/webauthn.rb.
  class PasskeysController < ApiController
    skip_before_action :authenticate_user_from_token!,
                       only: [ :authentication_options, :authenticate ]

    # GET /api/user/passkeys
    def index
      authorize Passkey.new(user: current_user), :index?

      passkeys = current_user.passkeys.recently_used_first.map { |passkey| serialize(passkey) }

      render json: { passkeys: passkeys }, status: :ok
    end

    # POST /api/user/passkeys/registration_options
    def registration_options
      authorize Passkey.new(user: current_user), :create?

      options = WebAuthn::Credential.options_for_create(
        user: {
          # Base64url like every credential id in these options, so the client
          # decodes every binary field the same way. The gem passes this value
          # through untouched, and nothing reads the handle back — we resolve
          # the account from the credential id.
          id:           Base64.urlsafe_encode64(current_user.public_id, padding: false),
          name:         current_user.email,
          display_name: current_user.full_name.presence || current_user.email
        },
        # Offering the credentials this account already holds stops an
        # authenticator from silently registering a second key for the same
        # account.
        exclude:                current_user.passkeys.pluck(:external_id),
        authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
      )

      record = WebauthnChallenge.issue!(
        challenge: options.challenge,
        purpose:   "registration",
        user:      current_user
      )

      render json: { handle: record.handle, options: options.as_json }, status: :ok
    end

    # POST /api/user/passkeys
    def create
      passkey = Passkey.new(user: current_user)
      authorize passkey, :create?

      challenge = WebauthnChallenge.consume(handle: params[:handle], purpose: "registration")

      if challenge.nil? || challenge.user_id != current_user.id
        render json: { error: "Passkey registration expired. Start again." }, status: :unprocessable_content
        return
      end

      credential = WebAuthn::Credential.from_create(registration_credential_params)
      credential.verify(challenge.challenge)

      passkey.assign_attributes(
        external_id: credential.id,
        public_key:  credential.public_key,
        sign_count:  credential.sign_count,
        nickname:    params[:nickname].to_s.strip.presence || default_nickname
      )
      passkey.save!

      render json: { passkey: serialize(passkey) }, status: :created
    rescue WebAuthn::Error => e
      Rails.logger.warn("Passkey registration rejected for user #{current_user.id}: #{e.class} #{e.message}")
      render json: { error: "Could not verify this passkey" }, status: :unprocessable_content
    end

    # DELETE /api/user/passkeys/:passkey_id
    def destroy
      passkey = find_by_any_id(Passkey, params[:passkey_id])
      passkey = nil unless passkey&.user_id == current_user.id

      if passkey.nil?
        render json: { error: "Passkey not found" }, status: :not_found
        return
      end

      authorize passkey, :destroy?
      passkey.destroy!

      render json: { message: "Passkey removed" }, status: :ok
    end

    # POST /api/user/passkeys/authentication_options
    #
    # Unauthenticated: this is the start of a sign-in. No allow list is sent, so
    # the browser offers whichever discoverable passkey the device holds and we
    # never reveal whether a given account has one.
    def authentication_options
      options = WebAuthn::Credential.options_for_get(user_verification: "preferred")

      record = WebauthnChallenge.issue!(challenge: options.challenge, purpose: "authentication")

      render json: { handle: record.handle, options: options.as_json }, status: :ok
    end

    # POST /api/user/passkeys/authenticate
    #
    # Unauthenticated. Returns the same body as onboarding, so the extension can
    # reuse one code path for "I have a token now".
    def authenticate
      challenge = WebauthnChallenge.consume(handle: params[:handle], purpose: "authentication")

      if challenge.nil?
        render json: { error: "Sign-in expired. Start again." }, status: :unauthorized
        return
      end

      credential = WebAuthn::Credential.from_get(assertion_credential_params)
      passkey    = Passkey.find_by(external_id: credential.id)

      if passkey.nil?
        render json: { error: "Unknown passkey" }, status: :unauthorized
        return
      end

      credential.verify(
        challenge.challenge,
        public_key: passkey.public_key,
        sign_count: passkey.sign_count
      )

      passkey.record_use!(credential.sign_count)

      user  = passkey.user
      token = JsonWebTokenService.encode({ user_id: user.id })

      render json: {
        pub_id: user.public_id.delete_prefix("usr_"),
        jwt:    token
      }, status: :ok
    rescue WebAuthn::Error => e
      Rails.logger.warn("Passkey sign-in rejected: #{e.class} #{e.message}")
      render json: { error: "Could not verify this passkey" }, status: :unauthorized
    end

    private

    # The exact keys WebAuthn::Credential reads. The clientExtensionResults hash
    # is open ended and nothing here consults it, so it stays out.
    CREDENTIAL_KEYS = [ :type, :id, :rawId, :authenticatorAttachment ].freeze

    def registration_credential_params
      params.require(:credential).permit(
        *CREDENTIAL_KEYS,
        response: [ :attestationObject, :clientDataJSON ]
      ).to_h
    end

    def assertion_credential_params
      params.require(:credential).permit(
        *CREDENTIAL_KEYS,
        response: [ :authenticatorData, :clientDataJSON, :signature, :userHandle ]
      ).to_h
    end

    def default_nickname
      taken = current_user.passkeys.pluck(:nickname)
      return "Passkey" if taken.exclude?("Passkey")

      index = 2
      index += 1 while taken.include?("Passkey #{index}")
      "Passkey #{index}"
    end

    def serialize(passkey)
      {
        id:           passkey.public_id,
        nickname:     passkey.nickname,
        created_at:   passkey.created_at,
        last_used_at: passkey.last_used_at
      }
    end
  end
end
