# frozen_string_literal: true

# Adds the RateLimit-Policy and RateLimit fields to every API response, so a
# client can slow down before it gets a 429. The fields follow the IETF draft
# "RateLimit header fields for HTTP":
# https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers-11
#
#   RateLimit-Policy: "req/ip";q=600;w=300, "catalog/ip";q=300;w=60
#   RateLimit: "req/ip";r=599;t=180, "catalog/ip";r=299;t=42
#
# Rack::Attack puts each throttle that counted the request in
# env["rack.attack.throttle_data"]. Each of those throttles is one policy. A
# request that a safelist let through was not counted, so it gets no fields.
class RateLimitHeaders
  THROTTLE_DATA = "rack.attack.throttle_data"

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    throttles = env[THROTTLE_DATA]
    if throttles.present? && env["PATH_INFO"].to_s.start_with?("/api/")
      headers["ratelimit-policy"] = self.class.policy_field(throttles)
      headers["ratelimit"]        = self.class.limit_field(throttles)
    end

    [ status, headers, body ]
  end

  # q is the quota in requests. w is the window in seconds.
  def self.policy_field(throttles)
    throttles.map do |name, data|
      "#{sf_string(name)};q=#{data[:limit].to_i};w=#{data[:period].to_i}"
    end.join(", ")
  end

  # r is the quota that is left. t is the number of seconds until the window
  # resets.
  def self.limit_field(throttles)
    throttles.map do |name, data|
      period    = data[:period].to_i
      remaining = [ data[:limit].to_i - data[:count].to_i, 0 ].max
      reset     = period - (data[:epoch_time].to_i % period)

      "#{sf_string(name)};r=#{remaining};t=#{reset}"
    end.join(", ")
  end

  # A String in Structured Field Values (RFC 9651) escapes a backslash and a
  # double quote.
  def self.sf_string(value)
    %("#{value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }}")
  end
end

# Outside Rack::Attack, so the fields also go on the 429 that Rack::Attack
# returns itself.
Rails.application.config.middleware.insert_before Rack::Attack, RateLimitHeaders
