# frozen_string_literal: true

# The page that runs the WebAuthn ceremony.
#
# It lives here rather than in the extension so the origin the browser reports
# is this site's. A passkey is bound to WEBAUTHN_RP_ID, and an extension page
# reports its own origin (chrome-extension://<id>, or a per-installation random
# moz-extension://<uuid> on Firefox), which changes per build and per install and
# cannot be wildcarded. Running the prompt here keeps one origin for every
# browser, every build, and both stores.
#
# The extension opens this through chrome.identity.launchWebAuthFlow, the same
# way it opens Google, and gets a single-use code back on the redirect.
class PasskeysController < ApplicationController
  layout "sessions"

  skip_before_action :verify_authenticity_token

  # "authenticate" is the extension's spelling; "signin" is accepted too so a
  # build from either side of this change keeps working.
  MODES = %w[authenticate signin register].freeze

  def show
    @mode         = MODES.include?(params[:mode]) ? params[:mode] : "authenticate"
    @redirect_uri = params[:redirect_uri].to_s
    @state        = params[:state].to_s
    @handoff      = params[:handoff].to_s
    # The extension names the device; it knows which machine this is and we do not.
    @nickname     = params[:nickname].to_s.strip.first(60)

    # Checked before anything is rendered: the page ends by sending a credential
    # to this address, so an unrecognised one must never reach the ceremony.
    unless PasskeyRedirectAllowlist.allows?(@redirect_uri)
      @error = "This link did not come from the WIT Calendar extension."
      render :error, status: :bad_request
      return
    end

    if @mode == "register" && @handoff.blank?
      @error = "This link is missing the part that says which account to add a passkey to."
      render :error, status: :bad_request
      nil
    end
  end
end
