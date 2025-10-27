module Api
  class EventsController < ApplicationController
    include ActionController::Live

    # Skip CSRF token verification for SSE endpoint
    skip_before_action :verify_authenticity_token, only: [:stream]
    # Skip modern browser requirement for API
    skip_before_action :allow_browser, if: -> { request.format.json? || request.format.text? }

    # GET /api/events/stream
    def stream
      # Set SSE headers
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no" # Disable Nginx buffering

      # Optional: Authenticate user via token
      # user = authenticate_from_token
      # return head :unauthorized unless user

      # Subscribe to Redis channel for events
      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))

      begin
        # Send initial connection event
        sse_write({ type: "connected", timestamp: Time.current.iso8601 })

        # Subscribe to Redis pub/sub channel
        redis.subscribe("sse_events") do |on|
          on.message do |channel, message|
            begin
              sse_write(JSON.parse(message))
            rescue JSON::ParserError => e
              Rails.logger.error("SSE: Failed to parse message: #{e.message}")
            end
          end
        end
      rescue IOError, Errno::EPIPE => e
        # Client disconnected
        Rails.logger.info("SSE: Client disconnected: #{e.message}")
      ensure
        # Clean up Redis connection
        redis.unsubscribe if redis
        redis.close if redis
        response.stream.close
      end
    end

    # GET /api/events/heartbeat
    # Lightweight endpoint for checking SSE support
    def heartbeat
      render json: { status: "ok", timestamp: Time.current.iso8601 }
    end

    private

    def sse_write(data)
      response.stream.write("data: #{data.to_json}\n\n")
    rescue IOError
      # Client disconnected, re-raise to exit the loop
      raise
    end

    # Optional: Token-based authentication for SSE
    def authenticate_from_token
      token = request.headers["Authorization"]&.gsub(/^Bearer /, "")
      return nil unless token

      begin
        decoded = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: "HS256" })
        User.find_by(id: decoded[0]["user_id"])
      rescue JWT::DecodeError
        nil
      end
    end
  end
end
