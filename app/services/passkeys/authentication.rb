# frozen_string_literal: true

module Passkeys
  # The passkey sign-in ceremony. The extension API ends it with a token and
  # the dashboard sign-in page with a cookie session; both run these two steps
  # and raise Passkeys::Failed.
  #
  # No allow list is sent, so the browser offers whichever discoverable passkey
  # the device holds, and the server never shows whether an account has one.
  module Authentication
    PURPOSE = "authentication"

    module_function

    # The first step: the options for navigator.credentials.get, and the handle
    # of the challenge for the second step.
    def options
      options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
      record  = WebauthnChallenge.issue!(challenge: options.challenge, purpose: PURPOSE)

      { handle: record.handle, options: options.as_json }
    end

    # The second step: spends the challenge, checks the signature, and returns
    # the passkey. The challenge is spent before the credential is read, so a
    # request with an expired handle answers :expired and a bad request still
    # uses up its challenge. A missing credential raises
    # ActionController::ParameterMissing (CredentialParams.assertion).
    def verify!(handle:, params:)
      challenge = WebauthnChallenge.consume(handle: handle, purpose: PURPOSE)
      raise Failed.new(:expired, ceremony: :authentication) if challenge.nil?

      assertion = WebAuthn::Credential.from_get(CredentialParams.assertion(params))
      passkey   = Passkey.find_by(external_id: assertion.id)
      raise Failed.new(:unknown, ceremony: :authentication) if passkey.nil?

      assertion.verify(challenge.challenge, public_key: passkey.public_key, sign_count: passkey.sign_count)
      passkey.record_use!(assertion.sign_count)
      passkey
    # ArgumentError: the gem raises it for a field that is not valid base64url.
    rescue WebAuthn::Error, ArgumentError => e
      Rails.logger.warn("Passkey sign-in rejected: #{e.class} #{e.message}")
      raise Failed.new(:rejected, ceremony: :authentication)
    end
  end
end
