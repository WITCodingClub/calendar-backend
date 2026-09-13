# frozen_string_literal: true

# Passkeys let a student who already onboarded sign in again on a new device
# without repeating the Google flow.
#
# WEBAUTHN_RP_ID   — the registrable domain: "calendar.witcc.dev" in production
# WEBAUTHN_ORIGINS — comma-separated **website** origins allowed to run the
#                    ceremony: "https://calendar.witcc.dev" in production,
#                    "https://staging-calendar.witcc.dev" in staging
#
# Both are required in production. A passkey registered against one relying
# party id cannot be used against another, so changing WEBAUTHN_RP_ID after
# launch invalidates every passkey already registered.
#
# Only website origins belong in WEBAUTHN_ORIGINS. A browser extension can run
# the ceremony itself, but then the origin it reports is its own
# (chrome-extension://<id>, or a per-installation random moz-extension://<uuid>
# on Firefox), and the list takes no wildcards. An unpacked build with no
# manifest key gets a fresh id, so production config would have to chase
# extension ids to keep anyone working. The credential is bound to
# WEBAUTHN_RP_ID, not to whoever ran the prompt, so the extension instead opens
# a page on this site and the origin stays the site's for every browser and
# every build.
WebAuthn.configure do |config|
  origins = ENV["WEBAUTHN_ORIGINS"].to_s.split(",").map(&:strip).reject(&:empty?)
  rp_id   = ENV["WEBAUTHN_RP_ID"].presence

  # The test suite must not depend on a developer's local tunnel, so it pins its
  # own values rather than reading whatever .env happens to hold.
  if Rails.env.test?
    origins = [ "http://localhost:3000" ]
    rp_id   = "localhost"
  elsif Rails.env.local?
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
