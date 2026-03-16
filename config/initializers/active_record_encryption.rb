# frozen_string_literal: true

# Configure Active Record encryption from environment variables (for CI)
# when credentials are not available.
#
# NOTE: This must set ActiveRecord::Encryption.config directly (not
# Rails.application.config.active_record.encryption) because by the time
# initializers run, the AR Encryption railtie has already called
# ActiveRecord::Encryption.configure, which creates a separate config object
# disconnected from the Rails application config proxy.
if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
  ActiveRecord::Encryption.config.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  ActiveRecord::Encryption.config.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", nil)
  ActiveRecord::Encryption.config.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", nil)
end
