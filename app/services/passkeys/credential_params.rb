# frozen_string_literal: true

module Passkeys
  # The credential that a browser sends back from a WebAuthn ceremony, with
  # the exact keys WebAuthn::Credential reads. The clientExtensionResults hash
  # is open ended and nothing here reads it, so it stays out.
  module CredentialParams
    KEYS = %i[type id rawId authenticatorAttachment].freeze
    ASSERTION_KEYS = %i[authenticatorData clientDataJSON signature userHandle].freeze
    ATTESTATION_KEYS = %i[attestationObject clientDataJSON].freeze

    module_function

    # The gem reads credential["response"] without a nil check, so a missing
    # response raises ActionController::ParameterMissing here, not a
    # NoMethodError in the gem.
    def assertion(params) = read(params, ASSERTION_KEYS)
    def attestation(params) = read(params, ATTESTATION_KEYS)

    def read(params, response_keys)
      credential = params.require(:credential)
      credential.require(:response)
      credential.permit(*KEYS, response: response_keys).to_h
    end
  end
end
