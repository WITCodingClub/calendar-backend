# frozen_string_literal: true

Rails.application.configure do
  ENV["STATSD_ENV"] = "production" # We need to override this, because this won't send data unless set to production
  ENV["STATSD_ADDR"] = "statsd.hogwarts.dev:8125" # This is the address of the StatsD server
  ENV["STATSD_PREFIX"] = "witccdotdev.server.#{Rails.env}" # This is the prefix for the StatsD metrics

  StatsD::Instrument::Environment.setup

  # Disable debug logging in development (reduces console spam)
  StatsD.logger = Logger.new(nil) if Rails.env.development?

  StatsD.increment("startup", 1)
end