# frozen_string_literal: true

class Rack::Attack
  # Use Rails.cache (Solid Cache in production, memory store in dev/test)
  Rack::Attack.cache.store = Rails.cache

  # ===========================================================================
  # SAFELISTS
  # ===========================================================================

  safelist("disable-rack-attack") { |_req| ENV["DISABLE_RACK_ATTACK"] == "true" }

  safelist("allow-localhost") do |req|
    ["127.0.0.1", "::1"].include?(req.ip) if Rails.env.development?
  end

  safelist("allow-healthchecks") do |req|
    req.path.start_with?("/up", "/healthchecks")
  end

  # Admins and users with the bypass flag skip per-user API limits
  safelist("allow-privileged-users") do |req|
    next false unless req.path.start_with?("/api/")

    user_id = extract_user_id_from_jwt(req)
    next false unless user_id

    user = User.find_by(id: user_id)
    user&.admin_access? || (user && Flipper.enabled?(FlipperFlags::BYPASS_RATE_LIMITS, user))
  end

  # ===========================================================================
  # BLOCKLISTS
  # ===========================================================================

  blocklist("block-suspicious-requests") do |req|
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 5, findtime: 10.minutes, bantime: 1.hour) do
      CGI.unescape(req.query_string) =~ /\/etc\/passwd/ ||
        req.path.include?("/etc/passwd") ||
        req.path.include?("wp-admin") ||
        req.path.include?("wp-login") ||
        req.path.include?("phpMyAdmin") ||
        req.path.include?(".env") ||
        req.path.include?("..")
    end
  end

  blocklist("block-suspicious-agents") do |req|
    next false if Rails.env.test?

    ua = req.user_agent.to_s.downcase
    ua.include?("scraper") ||
      (ua.include?("bot") && ua.exclude?("googlebot")) ||
      ua.include?("crawler") ||
      ua.empty?
  end

  # ===========================================================================
  # GLOBAL THROTTLES
  # ===========================================================================

  throttle("req/ip", limit: 600, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets", "/packs", "/rails/active_storage")
  end

  # ===========================================================================
  # OAUTH THROTTLES
  # ===========================================================================

  throttle("oauth/callbacks", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/auth/", "/oauth/")
  end

  # ===========================================================================
  # API THROTTLES
  # ===========================================================================

  throttle("api/user", limit: 100, period: 1.minute) do |req|
    extract_user_id_from_jwt(req) if req.path.start_with?("/api/")
  end

  throttle("api/ip", limit: 20, period: 1.minute) do |req|
    if req.path.start_with?("/api/") && !extract_user_id_from_jwt(req)
      req.ip
    end
  end

  throttle("api/process-courses", limit: 5, period: 1.minute) do |req|
    user_id = extract_user_id_from_jwt(req)
    "process-courses:#{user_id}" if req.path == "/api/process_courses" && req.post? && user_id
  end

  throttle("api/preview-template", limit: 10, period: 1.minute) do |req|
    user_id = extract_user_id_from_jwt(req)
    "preview:#{user_id}" if req.path == "/api/calendar_preferences/preview" && req.post? && user_id
  end

  # ===========================================================================
  # CALENDAR FEED THROTTLES
  # ===========================================================================

  throttle("calendar/token", limit: 60, period: 1.hour) do |req|
    req.path.split("/").last if req.path.start_with?("/calendar/")
  end

  throttle("calendar/ip", limit: 100, period: 1.hour) do |req|
    req.ip if req.path.start_with?("/calendar/")
  end

  # ===========================================================================
  # ADMIN THROTTLES
  # ===========================================================================

  throttle("admin/session", limit: 1000, period: 5.minutes) do |req|
    if req.path.start_with?("/admin")
      req.session[:session_id] || req.cookies["_session_id"]
    end
  end

  throttle("admin/destructive", limit: 100, period: 1.minute) do |req|
    if req.path.start_with?("/admin") && (req.delete? || req.path.include?("revoke") || req.path.include?("destroy"))
      req.session[:session_id] || req.cookies["_session_id"]
    end
  end

  # ===========================================================================
  # CUSTOM RESPONSES
  # ===========================================================================

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

    body = { error: "Rate limit exceeded", message: "Too many requests. Please try again later.", retry_after: match_data[:period] }.to_json

    [429, headers, [body]]
  end

  self.blocklisted_responder = lambda do |_request|
    [403, { "Content-Type" => "application/json" }, [{ error: "Forbidden", message: "Request blocked" }.to_json]]
  end

  # ===========================================================================
  # HELPERS
  # ===========================================================================

  def self.extract_user_id_from_jwt(req)
    auth_header = req.env["HTTP_AUTHORIZATION"]
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split.last
    payload = JWT.decode(token, nil, false).first
    payload["user_id"]
  rescue JWT::DecodeError, StandardError
    nil
  end
end
