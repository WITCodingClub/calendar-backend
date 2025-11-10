# frozen_string_literal: true

Rails.application.configure do
  # StatsD config here
  ENV["STATSD_ENV"] = "production" # This won't send data unless set to production
  ENV["STATSD_ADDR"] = "telemetry.hogwarts.dev:8125" # This is the address of the StatsD server
  ENV["STATSD_PREFIX"] = "witccdotdev.server.#{Rails.env}" # This is the prefix for the StatsD metrics

  StatsD::Instrument::Environment.setup

  StatsD.increment("startup", 1)
end