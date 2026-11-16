# frozen_string_literal: true

module Passkeys
  # The passkey registration ceremony for a signed-in user: the options with a
  # challenge, then the check of what the authenticator made. It raises
  # Passkeys::Failed. The caller authorizes with PasskeyPolicy#create?.
  module Registration
    PURPOSE = "registration"
    DEFAULT_NICKNAME = "Passkey"

    module_function

    # The options for navigator.credentials.create, and the handle of the
    # challenge for the second step.
    def options(user)
      options = WebAuthn::Credential.options_for_create(
        user: {
          # Base64url like every credential id in these options, so the client
          # decodes every binary field the same way. Nothing reads the handle
          # back: the account comes from the credential id.
          id:           Base64.urlsafe_encode64(user.public_id, padding: false),
          name:         user.email,
          display_name: user.full_name.presence || user.email
        },
        # Offering the credentials this account already holds stops an
        # authenticator from silently registering a second key for the same
        # account.
        exclude:                 user.passkeys.pluck(:external_id),
        authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
      )
      record = WebauthnChallenge.issue!(challenge: options.challenge, purpose: PURPOSE, user: user)

      { handle: record.handle, options: options.as_json }
    end

    # The second step: spends the challenge, checks the attestation, and saves
    # the passkey. A missing credential raises ActionController::ParameterMissing
    # (CredentialParams.attestation).
    def create!(user:, handle:, params:, nickname: nil)
      challenge = WebauthnChallenge.consume(handle: handle, purpose: PURPOSE)
      # Holding the handle is not authority to register. The caller proved who
      # they are with a token or a handoff, and the challenge has to belong to
      # that same account. Otherwise a leaked handle would let anyone attach
      # their own authenticator to someone else's account.
      raise Failed.new(:expired, ceremony: :registration) if challenge.nil? || challenge.user_id != user.id

      credential = WebAuthn::Credential.from_create(CredentialParams.attestation(params))
      credential.verify(challenge.challenge)

      user.passkeys.create!(
        external_id: credential.id,
        public_key:  credential.public_key,
        sign_count:  credential.sign_count,
        nickname:    nickname.to_s.strip.presence || default_nickname(user)
      )
    # ArgumentError: the gem raises it for a field that is not valid base64url.
    rescue WebAuthn::Error, ArgumentError => e
      Rails.logger.warn("Passkey registration rejected: #{e.class} #{e.message}")
      raise Failed.new(:rejected, ceremony: :registration)
    end

    # "Passkey", then "Passkey 2", "Passkey 3", and so on.
    def default_nickname(user)
      taken = user.passkeys.pluck(:nickname)
      return DEFAULT_NICKNAME if taken.exclude?(DEFAULT_NICKNAME)

      index = 2
      index += 1 while taken.include?("#{DEFAULT_NICKNAME} #{index}")
      "#{DEFAULT_NICKNAME} #{index}"
    end
  end
end
