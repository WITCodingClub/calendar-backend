# frozen_string_literal: true

# Decides where the passkey page may send a handoff code.
#
# Without this the page is an open redirect that carries a credential: anyone
# could send a student to /passkey?redirect_uri=https://evil.example and collect
# a working session after they touch their authenticator.
#
# The allowed values are the browser-generated redirect URLs of our own
# extension, the same ones the Google flow uses. Note what this is *not*: it is
# not WEBAUTHN_ORIGINS. An unrecognised redirect fails loudly and immediately,
# and it invalidates nobody's credential, whereas an origin the browser does not
# expect makes every registered passkey unusable. That is why the extension id
# belongs here and not there.
class PasskeyRedirectAllowlist
  # chrome.identity.getRedirectURL() shapes, per browser.
  CHROME_SUFFIX  = ".chromiumapp.org"
  FIREFOX_SUFFIX = ".extensions.allizom.org"

  def self.allows?(uri)
    new.allows?(uri)
  end

  def allows?(uri)
    return false if uri.blank?

    parsed = URI.parse(uri.to_s)
    return false unless parsed.scheme == "https"
    return false if parsed.host.blank?

    return true if configured.include?(normalise(parsed))

    # With nothing configured, accept our own extension's redirect shapes so a
    # local build works without ceremony. Production should set the variable.
    return false if configured.any?

    parsed.host.end_with?(CHROME_SUFFIX) || parsed.host.end_with?(FIREFOX_SUFFIX)
  rescue URI::InvalidURIError
    false
  end

  private

  # PASSKEY_REDIRECT_URIS — comma-separated exact URLs, e.g.
  # "https://<chrome-id>.chromiumapp.org/,https://<firefox-id>.extensions.allizom.org/"
  def configured
    @configured ||= ENV["PASSKEY_REDIRECT_URIS"].to_s
                       .split(",")
                       .map(&:strip)
                       .reject(&:blank?)
                       .filter_map { |value| normalise(URI.parse(value)) rescue nil }
  end

  # Compare on scheme, host and path only. A query or fragment on a registered
  # value would make an exact match brittle for no gain.
  def normalise(parsed)
    return nil if parsed.host.blank?

    path = parsed.path.presence || "/"
    "#{parsed.scheme}://#{parsed.host.downcase}#{path}"
  end
end
