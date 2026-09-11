# frozen_string_literal: true

# Passkeys let a student who already onboarded sign in again on a new device
# without repeating the Google flow. The relying party is this backend, so the
# id is the bare host, and the allowed origins list every front end that may run
# the ceremony: the dashboard and the browser extension.
#
# WEBAUTHN_RP_ID   — the registrable domain, e.g. "calendar.witcodingclub.com"
# WEBAUTHN_ORIGINS — comma-separated origins, e.g.
#                    "https://calendar.witcodingclub.com,chrome-extension://abc123"
#
# Both are required in production. A passkey registered against one relying
# party id cannot be used against another, so changing WEBAUTHN_RP_ID after
# launch invalidates every passkey already registered.
WebAuthn.configure do |config|
  origins = ENV["WEBAUTHN_ORIGINS"].to_s.split(",").map(&:strip).reject(&:empty?)
  rp_id   = ENV["WEBAUTHN_RP_ID"].presence

  if Rails.env.local? || Rails.env.test?
    origins = [ "http://localhost:3000" ] if origins.empty?
    rp_id ||= "localhost"
  end

  config.allowed_origins = origins
  config.rp_id           = rp_id if rp_id
  config.rp_name         = "WIT Calendar"

  # A passkey is a convenience credential for an account that Google already
  # vouched for, so we do not need an attestation statement about the make and
  # model of the authenticator. Skipping it also keeps hardware keys, phones,
  # and platform authenticators all usable.
  config.verify_attestation_statement = false

  config.credential_options_timeout = 120_000
end
