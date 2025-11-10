# frozen_string_literal: true

# Configure rate limiting for Google Calendar API calls
#
# Google Calendar API Quotas (default):
# - Queries per day: 1,000,000
# - Queries per 100 seconds per user: 1,500
# - Queries per 100 seconds: 20,000
#
# This configuration provides exponential backoff and retry logic to handle rate limits gracefully
Rails.application.config.to_prepare do
  # Configure GoogleApiRateLimiter settings
  GoogleCalendarService.configure_rate_limiting do |config|
    # Maximum number of retry attempts for rate-limited requests
    config.max_retries = ENV.fetch("GOOGLE_API_MAX_RETRIES", 5).to_i

    # Initial delay in seconds before first retry
    config.initial_delay = ENV.fetch("GOOGLE_API_INITIAL_DELAY", 1.0).to_f

    # Maximum delay in seconds between retries (caps exponential backoff)
    config.max_delay = ENV.fetch("GOOGLE_API_MAX_DELAY", 32.0).to_f

    # Multiplier for exponential backoff (delay doubles by default)
    config.backoff_multiplier = ENV.fetch("GOOGLE_API_BACKOFF_MULTIPLIER", 2.0).to_f

    # Delay in seconds between batch operations to avoid hitting rate limits
    # Lower values = faster processing but higher risk of rate limits
    # Higher values = slower processing but safer
    config.batch_throttle_delay = ENV.fetch("GOOGLE_API_BATCH_THROTTLE_DELAY", 0.1).to_f
  end
end
