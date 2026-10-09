# frozen_string_literal: true

# Stops a production boot that has no Active Record encryption key.
#
# Rails reads the keys lazily. With no key, the app boots, but the first read
# or save of a token raises ActiveRecord::Encryption::Errors::Configuration. That breaks sign-in and
# token refresh with no sign at deploy time. A failed boot names the missing
# env vars instead, and the container that runs `bin/rails db:prepare` stops
# before it serves a request.
module ActiveRecordEncryptionKeys
  class MissingKeyError < StandardError; end

  module_function

  # The env var names of the keys that neither ENV nor credentials give.
  def missing(env: ENV, credentials: Rails.application.credentials)
    Calendar::Application::ACTIVE_RECORD_ENCRYPTION_ENV.filter_map do |key, env_var|
      next if env[env_var].present?
      next if credentials.dig(:active_record_encryption, key).present?

      env_var
    end
  end

  def verify!(**)
    names = missing(**)
    return if names.empty?

    raise MissingKeyError,
          "Active Record encryption keys are missing: #{names.join(', ')}. " \
          "OauthCredential encrypts its tokens and cannot save without them. " \
          "Generate keys with `bin/rails db:encryption:init` and set these env vars " \
          "(or active_record_encryption in credentials)."
  end

  # The Docker build precompiles assets with SECRET_KEY_BASE_DUMMY and no
  # runtime env. It needs no keys.
  def check_at_boot?(env: ENV)
    Rails.env.production? && env["SECRET_KEY_BASE_DUMMY"].blank?
  end
end

ActiveRecordEncryptionKeys.verify! if ActiveRecordEncryptionKeys.check_at_boot?
