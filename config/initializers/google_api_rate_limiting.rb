# frozen_string_literal: true

Rails.application.config.to_prepare do
  GoogleCalendarService.configure_rate_limiting do |config|
    config.max_retries          = ENV.fetch("GOOGLE_API_MAX_RETRIES", 5).to_i
    config.initial_delay        = ENV.fetch("GOOGLE_API_INITIAL_DELAY", 1.0).to_f
    config.max_delay            = ENV.fetch("GOOGLE_API_MAX_DELAY", 32.0).to_f
    config.backoff_multiplier   = ENV.fetch("GOOGLE_API_BACKOFF_MULTIPLIER", 2.0).to_f
    config.batch_throttle_delay = ENV.fetch("GOOGLE_API_BATCH_THROTTLE_DELAY", 0.1).to_f
  end
end
