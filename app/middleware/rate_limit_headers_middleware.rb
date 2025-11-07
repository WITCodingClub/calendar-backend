# frozen_string_literal: true

# Middleware to add rate limit headers to all responses
class RateLimitHeadersMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Add rate limit headers if they were set by Rack::Attack
    if env["rack.attack.rate_limit_headers"]
      headers.merge!(env["rack.attack.rate_limit_headers"])
    end

    [status, headers, response]
  end
end
