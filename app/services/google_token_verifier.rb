# frozen_string_literal: true

# Verifies a Google-issued OAuth access token server-side.
#
# The Chrome extension obtains a token for the signed-in Google user (via
# chrome.identity) and sends it to /api/user/onboard. We validate it against
# Google's tokeninfo endpoint, confirm it was issued to *our* OAuth client
# (audience check, prevents token replay from other apps), and return the
# Google-verified email. This is what lets onboard trust the email instead of
# accepting whatever string the caller sends.
class GoogleTokenVerifier
  TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
  OPEN_TIMEOUT  = 5
  READ_TIMEOUT  = 5

  Result = Struct.new(:success, :email, :email_verified, :error, keyword_init: true) do
    def success?
      success
    end
  end

  def self.verify_access_token(access_token)
    new.verify_access_token(access_token)
  end

  def verify_access_token(access_token)
    return failure("missing token") if access_token.blank?

    response = connection.get(TOKENINFO_URL, access_token: access_token)

    unless response.success?
      return failure("token rejected by Google (status #{response.status})")
    end

    info = response.body
    info = JSON.parse(info) if info.is_a?(String)

    audience = info["aud"] || info["azp"] || info["audience"] || info["issued_to"]
    unless audience.present? && allowed_client_ids.include?(audience)
      return failure("token audience mismatch")
    end

    email = info["email"].to_s.strip.downcase
    return failure("token has no email") if email.blank?

    Result.new(
      success:        true,
      email:          email,
      email_verified: info["email_verified"].to_s == "true" || info["verified_email"].to_s == "true"
    )
  rescue Faraday::Error, JSON::ParserError => e
    failure("token verification failed: #{e.message}")
  end

  private

  # The token may be issued to the web OAuth client (dashboard/calendar flow) or
  # the Chrome extension's own OAuth client. Both are accepted; add the
  # extension client id to GOOGLE_OAUTH_CLIENT_IDS (comma-separated). Mirrors the
  # audience allowlist used by RiscValidationService.
  def allowed_client_ids
    @allowed_client_ids ||= begin
      ids = ENV["GOOGLE_OAUTH_CLIENT_IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
      web_client_id = Rails.application.credentials.dig(:google, :client_id)
      ids << web_client_id if web_client_id.present?
      ids.uniq
    end
  end

  def failure(message)
    Result.new(success: false, error: message)
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout      = READ_TIMEOUT
      f.response :json, content_type: /\bjson$/
    end
  end
end
