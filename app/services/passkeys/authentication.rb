# frozen_string_literal: true

module Passkeys
  # The passkey sign-in ceremony. The extension API ends it with a token and
  # the dashboard sign-in page with a cookie session; both run these two steps.
  #
  # No allow list is sent, so the browser offers whichever discoverable passkey
  # the device holds, and the server never shows whether an account has one.
  module Authentication
    PURPOSE = "authentication"

    # +reason+ is :expired (no live challenge for the handle), :unknown (no
    # passkey with that credential id) or :rejected (the signature or a field
    # did not verify).
    class Failed < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    module_function

    # The first step: the options for navigator.credentials.get, and the handle
    # of the challenge for the second step.
    def options
      options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
      record  = WebauthnChallenge.issue!(challenge: options.challenge, purpose: PURPOSE)

      { handle: record.handle, options: options.as_json }
    end

    # The second step: spends the challenge, checks the signature, and returns
    # the passkey. +credential+ comes from CredentialParams.assertion.
    def verify!(handle:, credential:)
      challenge = WebauthnChallenge.consume(handle: handle, purpose: PURPOSE)
      raise Failed, :expired if challenge.nil?

      assertion = WebAuthn::Credential.from_get(credential)
      passkey   = Passkey.find_by(external_id: assertion.id)
      raise Failed, :unknown if passkey.nil?

      assertion.verify(challenge.challenge, public_key: passkey.public_key, sign_count: passkey.sign_count)
      passkey.record_use!(assertion.sign_count)
      passkey
    # ArgumentError: the gem raises it for a field that is not valid base64url.
    rescue WebAuthn::Error, ArgumentError => e
      Rails.logger.warn("Passkey sign-in rejected: #{e.class} #{e.message}")
      raise Failed, :rejected
    end
  end
end
