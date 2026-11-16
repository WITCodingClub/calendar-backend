Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.action_dispatch.show_exceptions = :rescuable

  config.action_controller.allow_forgery_protection = false

  config.active_storage.service = :test

  config.active_job.queue_adapter = :test

  config.action_mailer.delivery_method = :test

  config.action_mailer.default_url_options     = { host: "example.com" }
  config.action_controller.default_url_options = { host: "example.com" }

  config.active_support.deprecation = :stderr

  config.action_controller.raise_on_missing_callback_actions = true

  # Throwaway keys so encrypted attributes (OAuth tokens, Audits1984 audit
  # notes) work without credentials. They win over the env vars, so specs give
  # the same result on every machine. Never reuse them outside the test
  # environment.
  config.active_record.encryption.primary_key = "test-primary-key-not-a-secret"
  config.active_record.encryption.deterministic_key = "test-deterministic-key-not-a-secret"
  config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-not-a-secret"
end
