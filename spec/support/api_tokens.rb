# frozen_string_literal: true

# Every API token is backed by a UserSession, because that is what makes it
# revocable. Specs need a real one, not a bare encode.
module ApiTokens
  def api_token_for(user, source: "google_onboard", **options)
    JsonWebTokenService.issue(user: user, source: source, **options)
  end

  def auth_headers_for(user, **options)
    { "Authorization" => "Bearer #{api_token_for(user, **options)}" }
  end
end

RSpec.configure do |config|
  config.include ApiTokens
end
