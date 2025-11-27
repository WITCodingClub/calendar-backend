# frozen_string_literal: true

Hashid::Rails.configure do |config|
  # Use a unique salt for this application (pulls from credentials)
  config.salt = Rails.application.credentials.secret_key_base || Rails.application.secret_key_base

  # Minimum length for hashids (default is 6)
  config.min_hash_length = 8

  # Character alphabet for hashids (default excludes ambiguous characters)
  config.alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
end
