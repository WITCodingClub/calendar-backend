# Configure Rack Attack for rate limiting
class Rack::Attack
  # Use Redis for Rack Attack storage
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/5" }
  )

  # Throttle all requests by IP (300 req/5 minutes)
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets')
  end

  # Throttle login attempts by email
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.params['user']&.dig('email')&.to_s&.downcase&.gsub(/\\s+/, "")
    end
  end

  # Throttle password reset attempts
  throttle('password_resets/email', limit: 3, period: 20.minutes) do |req|
    if req.path == '/users/password' && req.post?
      req.params['user']&.dig('email')&.to_s&.downcase&.gsub(/\\s+/, "")
    end
  end

  # Block suspicious requests
  blocklist('block suspicious requests') do |req|
    # Block requests with suspicious patterns
    Rack::Attack::Fail2Ban.filter("pentesters-\#{req.ip}", maxretry: 5, findtime: 10.minutes, bantime: 1.hour) do
      # Return true if this is a suspicious request
      CGI.unescape(req.query_string) =~ %r{/etc/passwd} ||
        req.path.include?('/etc/passwd') ||
        req.path.include?('wp-admin') ||
        req.path.include?('wp-login')
    end
  end

  # Always allow requests from localhost in development
  safelist('allow from localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1' if Rails.env.in?(%w[development development_wcreds])
  end
end
