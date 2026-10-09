require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Calendar
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # config/credentials/test.key exists without a matching test.yml.enc, so Rails
    # would try to decrypt credentials.yml.enc (master.key) with the wrong key. Fix
    # the path before credentials are first accessed.
    config.credentials.key_path = Rails.root.join("config", "master.key") if Rails.env.test?

    # Falls back to HASHID_SALT env var so CI can run without a master.key.
    config.hashid_salt = ENV.fetch("HASHID_SALT") { Rails.application.credentials.dig(:hashid, :salt) }

    # Active Record encryption keys. OAuth tokens (OauthCredential) and audit
    # notes use them. An env var wins. Without one, Rails reads the key from
    # credentials (active_record_encryption.<key>). Do not set nil here: a nil
    # in config hides the credentials value.
    # config/initializers/active_record_encryption.rb stops a production boot
    # that has no key.
    ACTIVE_RECORD_ENCRYPTION_ENV = {
      primary_key: "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
      deterministic_key: "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
      key_derivation_salt: "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
    }.freeze

    ACTIVE_RECORD_ENCRYPTION_ENV.each do |key, env_var|
      config.active_record.encryption[key] = ENV[env_var] if ENV[env_var].present?
    end

    # support_unencrypted_data stays at its default (false): an encrypted
    # column that holds plain text raises on read. Production ran
    # `bin/rails oauth_credentials:encrypt` on 2026-10-09 (#713). A local
    # database with older rows needs the same task.

    config.active_job.queue_adapter = :solid_queue

    # Single source of truth for the sender address. Action Mailer and Devise
    # both read it. The domain has to be one that is verified in Resend, so
    # do not point it back at wit.edu.
    config.x.mailer_from = ENV.fetch("MAILER_FROM", "WIT Calendar <noreply@send.witcc.dev>")

    # The Chrome Web Store page of the extension. The website (calendar-website,
    # src/lib/server/pages.ts) links to the same page.
    config.x.extension_install_url = ENV.fetch(
      "EXTENSION_INSTALL_URL",
      "https://chromewebstore.google.com/detail/wit-calendar/aceelinogfcceklkpacakdeddnaakicj"
    )

    config.mission_control.jobs.base_controller_class = "Admin::JobsBaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Eastern Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.exceptions_app = self.routes

    config.generators do |g|
      g.test_framework :rspec, fixtures: true, view_specs: false, helper_specs: false, routing_specs: false
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
