# Set Lockbox master key from credentials
if Rails.application.credentials.lockbox&.key?(:master_key)
  Lockbox.master_key = Rails.application.credentials.lockbox[:master_key]
else
  Rails.logger.warn "Lockbox master_key not found in credentials. Please add it by running: rails credentials:edit"
end
