# frozen_string_literal: true

module GoogleSignIn
  # Verifies a Google-issued OAuth access token server-side.
  #
  # The Chrome extension obtains a token for the signed-in Google user (via
  # chrome.identity) and sends it to /api/user/onboard. We validate it against
  # Google's tokeninfo endpoint, confirm it was issued to *our* OAuth client
  # (audience check, prevents token replay from other apps), and return the
  # Google-verified email. This is what lets onboard trust the email instead of
  # accepting whatever string the caller sends.
  class TokenVerifier
    TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
    READ_TIMEOUT  = 5

    Result = Struct.new(:success, :email, :email_verified, :error, keyword_init: true) do
      def success?
        success
      end

      def email_verified?
        email_verified
      end
    end

    def self.verify_access_token(access_token)
      new.verify_access_token(access_token)
    end

    def verify_access_token(access_token)
      return failure("missing token") if access_token.blank?

      response = OauthCredentials::Http.connection(read_timeout: READ_TIMEOUT).get(TOKENINFO_URL, access_token: access_token)

      unless response.success?
        return failure("token rejected by Google (status #{response.status})")
      end

      info = OauthCredentials::Http.parse(response.body)

      audience = info["aud"] || info["azp"] || info["audience"] || info["issued_to"]
      unless audience.present? && GoogleCalendar.client_ids.include?(audience)
        return failure("token audience mismatch")
      end

      email = info["email"].to_s.strip.downcase
      return failure("token has no email") if email.blank?

      Result.new(
        success:        true,
        email:          email,
        email_verified: info["email_verified"].to_s == "true" || info["verified_email"].to_s == "true"
      )
    rescue Faraday::Error => e
      failure("token verification failed: #{e.message}")
    end

    private

    def failure(message)
      Result.new(success: false, error: message)
    end
  end
end
