# frozen_string_literal: true

module Users
  # Signing in to the dashboard with a passkey.
  #
  # Same credential and same ceremony as the extension uses, but it ends
  # somewhere different: the extension wants a token, and the dashboard wants a
  # Devise cookie session. That is the whole reason this is not the API
  # controller.
  #
  # Nothing here creates an account. A passkey only exists on an account that
  # already signed in with its WIT Google account, so this widens who can get in
  # not at all — it only saves them the Google round trip.
  class PasskeySessionsController < ApplicationController
    # The ceremony runs on this page, so the request carries the usual CSRF
    # token; no need to skip verification the way the token API does.

    # POST /users/passkey/options
    def options
      options = WebAuthn::Credential.options_for_get(user_verification: "preferred")

      record = WebauthnChallenge.issue!(challenge: options.challenge, purpose: "authentication")

      render json: { handle: record.handle, options: options.as_json }, status: :ok
    end

    # POST /users/passkey/callback
    def create
      challenge = WebauthnChallenge.consume(handle: params[:handle], purpose: "authentication")

      if challenge.nil?
        render json: { error: "That sign-in attempt expired. Try again." }, status: :unauthorized
        return
      end

      credential = WebAuthn::Credential.from_get(credential_params)
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

      user = passkey.user
      # Stay signed in past the :timeoutable idle limit, as the Google sign-in does.
      user.remember_me = true
      sign_in(:user, user)

      render json: { redirect_to: after_sign_in_path_for(user) }, status: :ok
    rescue WebAuthn::Error => e
      Rails.logger.warn("Passkey sign-in rejected: #{e.class} #{e.message}")
      render json: { error: "Could not verify this passkey" }, status: :unauthorized
    end

    private

    CREDENTIAL_KEYS = [ :type, :id, :rawId, :authenticatorAttachment ].freeze

    def credential_params
      params.require(:credential).permit(
        *CREDENTIAL_KEYS,
        response: [ :authenticatorData, :clientDataJSON, :signature, :userHandle ]
      ).to_h
    end
  end
end
