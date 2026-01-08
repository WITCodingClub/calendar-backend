# frozen_string_literal: true

require Rails.root.join("app/lib/flipper_flags")

# Configure Rack Attack for rate limiting
class Rack::Attack
  # Use Redis for Rack Attack storage in production/staging, memory store in development/test
  Rack::Attack.cache.store = if Rails.env.production? || Rails.env.staging?
                               ActiveSupport::Cache::RedisCacheStore.new(
                                 url: ENV.fetch("REDIS_URL", "redis://localhost:6379/5")
                               )
                             else
                               ActiveSupport::Cache::MemoryStore.new
                             end

  # ============================================================================
  # SAFELISTS - Requests that bypass all rate limiting
  # ============================================================================

  # Disable rate limiting entirely in test environment
  # NOTE: Commented out to allow rate limiting tests to run
  # safelist("allow-test-environment") do |req|
  #   Rails.env.test?
  # end

  # Always allow requests from localhost in development
  safelist("allow-localhost") do |req|
    ["127.0.0.1", "::1"].include?(req.ip) if Rails.env.development?
  end

  # Allow health check endpoints (needed for monitoring/load balancers)
  safelist("allow-healthchecks") do |req|
    req.path.start_with?("/up", "/healthchecks", "/okcomputer")
  end

  # Whitelist admin users and users with bypass feature flag from most rate limits
  safelist("allow-privileged-users") do |req|
    # Skip for authentication endpoints (we still want to rate limit these for security)
    next false if ["/users/sign_in", "/users/password"].include?(req.path)

    # Check if this is an API request with privileged user
    if req.path.start_with?("/api/")
      user_id = extract_user_id_from_jwt(req)
      user_has_admin_access?(user_id) || user_has_rate_limit_bypass?(user_id)
    else
      # For non-API requests (including admin area), we rely on more generous limits
      # below instead of full whitelist since we can't easily check user from session
      false
    end
  end

  # ============================================================================
  # BLOCKLISTS - Malicious requests to block immediately
  # ============================================================================

  # Block suspicious requests with common attack patterns
  blocklist("block-suspicious-requests") do |req|
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 5, findtime: 10.minutes, bantime: 1.hour) do
      # Return true if this is a suspicious request
      CGI.unescape(req.query_string) =~ /\/etc\/passwd/ ||
        req.path.include?("/etc/passwd") ||
        req.path.include?("wp-admin") ||
        req.path.include?("wp-login") ||
        req.path.include?("phpMyAdmin") ||
        req.path.include?(".env") ||
        req.path.include?("..") # Path traversal attempt
    end
  end

  # Block requests with suspicious user agents
  blocklist("block-suspicious-agents") do |req|
    # Skip blocking in test environment
    next false if Rails.env.test?

    user_agent = req.user_agent.to_s.downcase
    user_agent.include?("scraper") ||
      (user_agent.include?("bot") && user_agent.exclude?("googlebot")) ||
      user_agent.include?("crawler") ||
      user_agent.empty?
  end

  # ============================================================================
  # GLOBAL THROTTLES - Apply to all requests
  # ============================================================================

  # General IP-based throttle (exclude static assets and safelisted paths)
  throttle("req/ip", limit: 600, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets", "/packs", "/rails/active_storage")
  end

  # ============================================================================
  # AUTHENTICATION THROTTLES
  # ============================================================================

  # Throttle login attempts by email (prevent credential stuffing)
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      email = req.params["user"]&.dig("email")
      email.to_s.downcase.gsub(/\s+/, "") if email.present?
    end
  end

  # Throttle login attempts by IP (prevent distributed attacks)
  throttle("logins/ip", limit: 20, period: 5.minutes) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Throttle password reset attempts by email
  throttle("password-resets/email", limit: 3, period: 20.minutes) do |req|
    if req.path == "/users/password" && req.post?
      email = req.params["user"]&.dig("email")
      email.to_s.downcase.gsub(/\s+/, "") if email.present?
    end
  end

  # Throttle password reset attempts by IP
  throttle("password-resets/ip", limit: 10, period: 20.minutes) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  # ============================================================================
  # OAUTH THROTTLES
  # ============================================================================

  # Throttle OAuth callbacks (prevent abuse of OAuth flow)
  throttle("oauth/callbacks", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/auth/", "/oauth/")
  end

  # ============================================================================
  # API THROTTLES - Authenticated Users
  # ============================================================================

  # Extract user ID from JWT token for API rate limiting
  def self.extract_user_id_from_jwt(req)
    return nil unless req.path.start_with?("/api/")

    auth_header = req.env["HTTP_AUTHORIZATION"]
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split.last
    begin
      # Decode JWT without verification (we only need the user_id for rate limiting)
      # The actual authentication is handled by the controller
      payload = JWT.decode(token, nil, false).first
      payload["user_id"]
    rescue JWT::DecodeError, StandardError
      nil
    end
  end

  # Check if user has admin access (admin, super_admin, or owner)
  def self.user_has_admin_access?(user_id)
    return false unless user_id

    begin
      user = User.find_by(id: user_id)
      user&.admin_access?
    rescue
      false
    end
  end

  # Check if user has rate limit bypass feature flag enabled
  def self.user_has_rate_limit_bypass?(user_id)
    return false unless user_id

    begin
      user = User.find_by(id: user_id)
      return false unless user

      Flipper.enabled?(FlipperFlags::BYPASS_RATE_LIMITS, user)
    rescue
      false
    end
  end

  # API requests by authenticated user (generous limit for legitimate users)
  throttle("api/user", limit: 100, period: 1.minute) do |req|
    extract_user_id_from_jwt(req) if req.path.start_with?("/api/")
  end

  # API requests by IP for unauthenticated/anonymous requests (strict limit)
  throttle("api/ip", limit: 20, period: 1.minute) do |req|
    if req.path.start_with?("/api/") && !extract_user_id_from_jwt(req)
      # Only apply if there's no valid user token
      req.ip
    end
  end

  # ============================================================================
  # API THROTTLES - Expensive Operations
  # ============================================================================

  # Course processing (expensive operation with external API calls)
  throttle("api/process-courses", limit: 5, period: 1.minute) do |req|
    user_id = extract_user_id_from_jwt(req)
    "process-courses:#{user_id}" if req.path == "/api/process_courses" && req.post? && user_id
  end

  # Template preview (computationally expensive)
  throttle("api/preview-template", limit: 10, period: 1.minute) do |req|
    user_id = extract_user_id_from_jwt(req)
    "preview:#{user_id}" if req.path == "/api/calendar_preferences/preview" && req.post? && user_id
  end

  # ============================================================================
  # CALENDAR FEED THROTTLES
  # ============================================================================

  # ICS calendar feed by token (allow reasonable polling but prevent abuse)
  throttle("calendar/token", limit: 60, period: 1.hour) do |req|
    if req.path.start_with?("/calendar/")
      # Extract calendar token from path
      req.path.split("/").last
    end
  end

  # ICS calendar feed by IP (backup protection)
  throttle("calendar/ip", limit: 100, period: 1.hour) do |req|
    req.ip if req.path.start_with?("/calendar/")
  end

  # ============================================================================
  # ADMIN AREA THROTTLES
  # ============================================================================

  # Admin area by user session (very generous limits for admin users)
  throttle("admin/session", limit: 1000, period: 5.minutes) do |req|
    if req.path.start_with?("/admin")
      # Use session ID for admin rate limiting
      req.session[:session_id] || req.cookies["_session_id"]
    end
  end

  # Admin destructive operations (delete, revoke, etc.) - generous but not unlimited for safety
  throttle("admin/destructive", limit: 100, period: 1.minute) do |req|
    if req.path.start_with?("/admin") && (req.delete? || req.path.include?("revoke") || req.path.include?("destroy"))
      req.session[:session_id] || req.cookies["_session_id"]
    end
  end

  # ============================================================================
  # CUSTOM RESPONSES
  # ============================================================================

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    headers = {
      "RateLimit-Limit"     => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset"     => (now + (match_data[:period] - (now % match_data[:period]))).to_s,
      "Content-Type"        => "application/json",
      "Retry-After"         => match_data[:period].to_s
    }

    body = {
      error: "Rate limit exceeded",
      message: "Too many requests. Please try again later.",
      retry_after: match_data[:period]
    }.to_json

    [429, headers, [body]]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |_request|
    [403, { "Content-Type" => "application/json" }, [{ error: "Forbidden", message: "Request blocked" }.to_json]]
  end

  # ============================================================================
  # TRACKING - Add rate limit headers to all responses
  # ============================================================================

  # Add rate limit headers to successful requests
  ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _request_id, payload|
    request = payload[:request]
    if request.env["rack.attack.throttle_data"]
      match_data = request.env["rack.attack.match_data"]
      now = match_data[:epoch_time]

      request.env["rack.attack.rate_limit_headers"] = {
        "RateLimit-Limit"     => match_data[:limit].to_s,
        "RateLimit-Remaining" => (match_data[:limit] - match_data[:count]).to_s,
        "RateLimit-Reset"     => (now + (match_data[:period] - (now % match_data[:period]))).to_s
      }
    end
  end

end

# RateLimitHeadersMiddleware disabled - was causing stack overflow
# TODO: Investigate and re-enable
# require_relative "../../app/middleware/rate_limit_headers_middleware"
# Rails.application.config.middleware.insert_after Rack::Attack, RateLimitHeadersMiddleware
