# frozen_string_literal: true

EncodedIds.configure do |config|
  # Hashid configuration (for integer IDs)
  config.hashid_salt = Rails.application.credentials.dig(:hashid, :salt) ||
                       Rails.application.secret_key_base
  config.hashid_min_length = 8
  config.hashid_alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

  # Base62 alphabet (for UUID encoding)
  config.base62_alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # Separator between prefix and hash
  config.separator = "_"

  # Whether to include prefix in to_param URLs
  config.use_prefix_in_routes = false
end
