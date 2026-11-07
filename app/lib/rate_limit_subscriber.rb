# frozen_string_literal: true

# Receives each request that a Rack::Attack throttle refuses with 429
# (config/initializers/rack_attack.rb subscribes it).
#
# For each refusal it adds one to calendar_rate_limited_total, by throttle
# name. Rack::Attack answers before Rails, so the request metrics and the
# Rails log never see these requests.
#
# It also writes one log line for the first refusal of each key in each
# window, so a flood of refused requests writes one line, not thousands. The
# line has no key: a key is an IP address, a user id, or a digest of a token.
class RateLimitSubscriber
  def self.call(request)
    data = request.env["rack.attack.match_data"] || {}
    throttle = request.env["rack.attack.matched"].to_s

    Yabeda.calendar.rate_limited_total.increment(throttle: throttle)
    log(throttle, data) if data[:count].to_i == data[:limit].to_i + 1
  rescue StandardError => e
    # A failure here must not turn a 429 into a 500.
    Rails.logger.warn("RateLimitSubscriber failed: #{e.class}: #{e.message}")
  end

  def self.log(throttle, data)
    Rails.logger.warn({
      message: "rate_limited",
      throttle: throttle,
      limit: data[:limit],
      period: data[:period]
    }.to_json)
  end
  private_class_method :log
end
