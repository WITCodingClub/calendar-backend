# frozen_string_literal: true

class Rack::Attack
  # Rack::Attack reads the cache on every request and rescues only Redis and
  # Dalli errors. Solid Cache rescues only timeouts and lost connections, so a
  # missing table or another database error would fail every request. This
  # wrapper reports the error and fails open: the request goes through without
  # a limit until the cache works again.
  class FailOpenStore < SimpleDelegator
    %i[read write increment delete].each do |method_name|
      define_method(method_name) do |*args, **options|
        __getobj__.public_send(method_name, *args, **options)
      rescue ActiveRecord::ActiveRecordError => error
        Rails.error.report(error, handled: true, severity: :warning, source: "rack_attack.cache")
        nil
      end
    end
  end

  # Use Rails.cache (Solid Cache in production, null store in test)
  Rack::Attack.cache.store = FailOpenStore.new(Rails.cache)

  # Public, unauthenticated catalog API. Kept as one predicate so the throttle
  # and blocklist rules below cannot drift apart.
  # /api/graphql only redirects to /api/v1/graphql, but it counts too, so a
  # client cannot use the redirect to skip the limit.
  GRAPHQL_PATHS = [ "/api/v1/graphql", "/api/graphql" ].freeze

  PUBLIC_CATALOG_PATH = lambda do |req|
    req.path.start_with?("/api/v1/catalog") || GRAPHQL_PATHS.include?(req.path)
  end

  # Files and docs written for search engines and AI agents. robots.txt tells
  # every agent it may read them, so the agent blocklist must not refuse them.
  AGENT_READABLE_PATHS = [ "/robots.txt", "/sitemap.xml", "/llms.txt" ].freeze

  # Anonymous usage events from the extension. Many students share one campus
  # IP address, so these get their own budget and do not use up the anonymous
  # API limit that sign-in needs.
  EXTENSION_EVENTS_PATH = "/api/extension_events"

  AGENT_READABLE_PATH = lambda do |req|
    AGENT_READABLE_PATHS.include?(req.path) ||
      req.path == "/docs" ||
      req.path.start_with?("/docs/") ||
      PUBLIC_CATALOG_PATH.call(req)
  end

  # ===========================================================================
  # SAFELISTS
  # ===========================================================================

  safelist("disable-rack-attack") { |_req| ENV["DISABLE_RACK_ATTACK"] == "true" }

  safelist("allow-localhost") do |req|
    [ "127.0.0.1", "::1" ].include?(req.ip) if Rails.env.development?
  end

  safelist("allow-healthchecks") do |req|
    req.path.start_with?("/up", "/healthchecks", "/okcomputer")
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

    suspicious_agent?(req)
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
    if req.path.start_with?("/api/") && !PUBLIC_CATALOG_PATH.call(req) &&
       req.path != EXTENSION_EVENTS_PATH && !extract_user_id_from_jwt(req)
      req.ip
    end
  end

  throttle("api/extension-events", limit: 120, period: 1.minute) do |req|
    req.ip if req.path == EXTENSION_EVENTS_PATH
  end

  # The public catalog API is meant to be consumed anonymously, so it gets its
  # own, more generous budget instead of the 20/min anonymous API limit.
  throttle("catalog/ip", limit: 300, period: 1.minute) do |req|
    req.ip if PUBLIC_CATALOG_PATH.call(req)
  end

  # A semantic search embeds the query, which costs an API call whenever the
  # words are new. The cache absorbs the repeats; this limit absorbs the rest.
  # Only the REST path is read here: GraphQL carries its query in the body, and
  # the 300/min catalog limit above already covers it.
  throttle("catalog/semantic", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/catalog") && req.GET["semantic"].present?
  end

  # The batch path shares this budget. A batch counts as one request, and it
  # processes only its first term inside the request.
  #
  # The router also accepts a format suffix ("/api/process_courses.json"), a
  # trailing slash, and repeated slashes. Normalize the path the same way the
  # router does, so these variants use the same budget.
  PROCESS_COURSES_PATH = %r{\A/api/process_courses(?:/batch)?(?:\.[^/.?]+)?\z}

  throttle("api/process-courses", limit: 5, period: 1.minute) do |req|
    path = ActionDispatch::Journey::Router::Utils.normalize_path(req.path)
    user_id = extract_user_id_from_jwt(req) if req.post? && PROCESS_COURSES_PATH.match?(path)
    "process-courses:#{user_id}" if user_id
  end

  throttle("api/preview-template", limit: 10, period: 1.minute) do |req|
    user_id = extract_user_id_from_jwt(req)
    "preview:#{user_id}" if req.path == "/api/calendar_preferences/preview" && req.post? && user_id
  end

  # Passkey sign-in and onboarding both mint a token without one, so they carry
  # no user to bucket by. Give them a tighter budget than the general anonymous
  # API limit, which guessing a credential would otherwise sit comfortably under.
  UNAUTHENTICATED_TOKEN_PATHS = [
    "/api/user/onboard",
    "/api/user/passkeys/authentication_options",
    "/api/user/passkeys/authenticate"
  ].freeze

  throttle("api/token-mint", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && UNAUTHENTICATED_TOKEN_PATHS.include?(req.path)
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
  # MEETING LINK THROTTLES
  # ===========================================================================

  # The public one-time meeting link page (/meet/:token). A guest needs a few
  # page views. A tight budget keeps anyone from guessing tokens, and a booking
  # sends an email and makes a calendar event, so picks get less.
  MEETING_LINK_PATH = %r{\A/meet/[^/]+(?:/sign_in)?\z}

  throttle("meet/ip", limit: 30, period: 1.minute) do |req|
    req.ip if MEETING_LINK_PATH.match?(req.path)
  end

  throttle("meet/pick/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.post? && MEETING_LINK_PATH.match?(req.path)
  end

  # One link gets a fixed budget, whatever the number of IP addresses. The
  # cache key holds a digest, so the cache never stores a working token.
  throttle("meet/token", limit: 60, period: 1.hour) do |req|
    "meet:#{OpenSSL::Digest::SHA256.hexdigest(req.path.split('/')[2])}" if MEETING_LINK_PATH.match?(req.path)
  end

  # ===========================================================================
  # ADMIN THROTTLES
  # ===========================================================================

  throttle("admin/session", limit: 1000, period: 5.minutes) do |req|
    req.cookies["_calendar_session"] if req.path.start_with?("/admin")
  end

  throttle("admin/destructive", limit: 100, period: 1.minute) do |req|
    if req.path.start_with?("/admin") && (req.delete? || req.path.include?("revoke") || req.path.include?("destroy"))
      req.cookies["_calendar_session"]
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

    body = {
      error:       "Rate limit exceeded",
      code:        "RATE_LIMITED",
      message:     "Too many requests. Please try again later.",
      retry_after: match_data[:period]
    }.to_json

    [ 429, headers, [ body ] ]
  end

  self.blocklisted_responder = lambda do |_request|
    body = { error: "Forbidden", code: "FORBIDDEN", message: "Request blocked" }.to_json

    [ 403, { "Content-Type" => "application/json" }, [ body ] ]
  end

  # ===========================================================================
  # HELPERS
  # ===========================================================================

  # Up to five rules ask for the user on one API request. Decode the token once
  # and keep the answer on the request.
  JWT_USER_ID_ENV_KEY = "rack.attack.jwt_user_id"

  # Crawlers, bots, and clients with no User-Agent get no access to the app
  # pages. Agents may still read the files and docs written for them, and data
  # tools, which often send no User-Agent, may still read the catalog API.
  def self.suspicious_agent?(req)
    return false if AGENT_READABLE_PATH.call(req)

    ua = req.user_agent.to_s.downcase
    suspicious = ua.include?("scraper") ||
                 (ua.include?("bot") && ua.exclude?("googlebot")) ||
                 ua.include?("crawler") ||
                 ua.empty?

    # Checked last, because it runs the router.
    suspicious && !unknown_path?(req)
  end

  # A path with no route gets the 404 page, which tells an agent that the page
  # does not exist and where to look instead. A 403 says that the page exists
  # and that the agent may not read it.
  def self.unknown_path?(req)
    Rails.application.routes.recognize_path(req.path, method: req.request_method)
    false
  rescue ActionController::RoutingError
    true
  rescue StandardError
    # A route constraint that needs a session, such as Devise's authenticate,
    # can raise here. That path is an app page, so keep blocking it.
    false
  end

  def self.extract_user_id_from_jwt(req)
    return req.env[JWT_USER_ID_ENV_KEY] if req.env.key?(JWT_USER_ID_ENV_KEY)

    req.env[JWT_USER_ID_ENV_KEY] = decode_user_id_from_jwt(req)
  end

  def self.decode_user_id_from_jwt(req)
    auth_header = req.env["HTTP_AUTHORIZATION"]
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split.last
    # Verify signature and expiration. A forged/unsigned token must not be able
    # to grant the admin throttle safelist or a controlled throttle-bucket key.
    payload = JsonWebTokenService.decode(token)
    payload && payload[:user_id]
  rescue StandardError
    nil
  end
end
