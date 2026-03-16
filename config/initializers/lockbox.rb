# frozen_string_literal: true

# Set Lockbox master key from credentials, falling back to an environment
# variable so that CI environments without a credentials key file still work.
if Rails.application.credentials.lockbox&.key?(:master_key)
  Lockbox.master_key = Rails.application.credentials.lockbox[:master_key]
elsif ENV["LOCKBOX_MASTER_KEY"].present?
  Lockbox.master_key = ENV["LOCKBOX_MASTER_KEY"]
else
  Rails.logger.warn "Lockbox master_key not found in credentials. Please add it by running: rails credentials:edit"
end
