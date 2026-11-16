# frozen_string_literal: true

# Reads the token from an Authorization header. Api::TokenAuthentication and
# Rack::Attack read the same header, so they read it the same way.
module BearerToken
  # The token, or nil for a missing or empty header.
  def self.from(authorization)
    authorization.to_s.sub(/\ABearer\s+/, "").presence
  end
end
