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

    config.active_job.queue_adapter = :solid_queue

    config.mission_control.jobs.base_controller_class = "Admin::ApplicationController"
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
