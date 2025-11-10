# frozen_string_literal: true

Rails.application.configure do
  # StatsD config here
  ENV["STATSD_ENV"] = Rails.env # Enable for all environments (development, production, etc.)
  ENV["STATSD_ADDR"] = "telemetry.hogwarts.dev:8125" # This is the address of the StatsD server
  ENV["STATSD_PREFIX"] = "witccdotdev.server.#{Rails.env}" # This is the prefix for the StatsD metrics

  StatsD::Instrument::Environment.setup

  # Disable debug logging in development (reduces console spam)
  StatsD.logger = Logger.new(nil) if Rails.env.development?

  StatsD.increment("startup", 1)
end