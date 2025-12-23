# frozen_string_literal: true

if defined?(Logster)
  Logster.config.application_version = ENV.fetch("GIT_SHA", nil)

  # Store logs in Redis for persistence across restarts
  redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/6")
  Logster.store = Logster::RedisStore.new(Redis.new(url: redis_url))

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

  # Broadcast Rails logs to Logster so they appear in the web UI
  Rails.application.config.after_initialize do
    if Rails.logger.respond_to?(:broadcast_to)
      # Rails 7.1+ uses broadcast_to
      Rails.logger.broadcast_to(Logster.logger)
    else
      # Rails < 7.1 fallback
      Rails.logger.extend(ActiveSupport::Logger.broadcast(Logster.logger))
    end
  end
end
