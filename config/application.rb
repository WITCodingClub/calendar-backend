# frozen_string_literal: true

require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WitCalendarBackend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Add constraints directory to autoload paths
    config.autoload_paths << Rails.root.join("app/constraints")
    config.autoload_paths << Rails.root.join("app/middleware")

    config.active_job.queue_adapter = :solid_queue

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.

    config.mission_control.jobs.base_controller_class = "Admin::BaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    config.time_zone = "Eastern Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")

    # Load and configure Rack::Attack middleware
    config.middleware.use Rack::Attack
    require_relative "../app/middleware/rate_limit_headers_middleware"
    config.middleware.insert_after Rack::Attack, RateLimitHeadersMiddleware
  end
end
