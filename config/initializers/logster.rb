# frozen_string_literal: true

if defined?(Logster)
  Logster.config.application_version = ENV.fetch("GIT_SHA", nil)

  # Store logs in Redis for persistence across restarts
  if ENV["REDIS_URL"].present?
    Logster.store = Logster::RedisStore.new(Redis.new(url: ENV["REDIS_URL"]))
  end

  # Group similar errors together
  Logster.config.enable_custom_patterns_via_ui = true

  # Keep more logs
  Logster.config.maximum_message_length = 10_000

  # Add request context to logs
  Logster.config.current_context = lambda {
    {
      request_id: Thread.current[:request_id]
    }
  }
end
