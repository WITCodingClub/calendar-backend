# frozen_string_literal: true

# Settings for "Sign in with Microsoft": the omniauth-entra-id strategy,
# registered as "microsoft" in config/initializers/omniauth.rb.
#
# It reads the same Entra app registration as the Microsoft Graph calendar
# provider (MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET, MICROSOFT_TENANT_ID).
# It asks only for the sign-in scopes, so it does not need the tenant admin
# consent that Graph calendar access needs. See docs/microsoft-sign-in.md.
module MicrosoftSignIn
  PROVIDER      = "microsoft"
  REQUEST_PATH  = "/auth/microsoft"
  CALLBACK_PATH = "/auth/microsoft/callback"
  SCOPE         = "openid email profile"

  TENANT_ID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  module_function

  def config
    {
      client_id:     ENV["MICROSOFT_CLIENT_ID"].presence,
      client_secret: ENV["MICROSOFT_CLIENT_SECRET"].presence,
      tenant_id:     ENV["MICROSOFT_TENANT_ID"].presence || "organizations"
    }
  end

  # Sign-in needs one tenant id, not "organizations". The strategy checks the
  # ID token issuer against the tenant, and that check fails for
  # "organizations". The tenant is also what makes the email trustworthy:
  # see MicrosoftSignIn::Authenticator.
  def configured?
    settings = config
    settings[:client_id].present? &&
      settings[:client_secret].present? &&
      settings[:tenant_id].match?(TENANT_ID_FORMAT)
  end

  # Checked with no actor. Nobody is signed in before a sign-in, so only a
  # global enable turns this on. Enabling the flag for a user or a group does
  # nothing here.
  def enabled?
    configured? && Flipper.enabled?(FlipperFlags::MICROSOFT_SIGN_IN)
  end

  # OmniAuth calls this for every request, so the cheap path check goes first.
  # Only a POST starts the sign-in, and a GET falls through to a 404.
  def request_phase?(env)
    env["PATH_INFO"] == REQUEST_PATH && env["REQUEST_METHOD"] == "POST" && enabled?
  end

  # The OmniAuth setup phase. Reads the settings per request, so the strategy
  # needs no values at boot.
  def configure_strategy(strategy)
    settings = config

    strategy.options.client_id     = settings[:client_id]
    strategy.options.client_secret = settings[:client_secret]
    strategy.options.tenant_id     = settings[:tenant_id]
  end
end
