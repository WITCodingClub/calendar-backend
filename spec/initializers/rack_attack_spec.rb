# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rack::Attack do
  let(:user) { create(:user) }

  def request_with(header)
    Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/user/email", "HTTP_AUTHORIZATION" => header))
  end

  describe ".suspicious_agent?" do
    def request_to(path, user_agent)
      Rack::Attack::Request.new(Rack::MockRequest.env_for(path, "HTTP_USER_AGENT" => user_agent))
    end

    [ "/robots.txt", "/sitemap.xml", "/llms.txt", "/docs", "/docs/api", "/docs/api.md" ].each do |path|
      it "lets a bot read #{path}" do
        expect(described_class.suspicious_agent?(request_to(path, "Mozilla/5.0 (compatible; ClaudeBot/1.0)"))).to be(false)
      end

      it "lets a client with no User-Agent read #{path}" do
        expect(described_class.suspicious_agent?(request_to(path, ""))).to be(false)
      end
    end

    it "lets a bot read the public catalog API" do
      expect(described_class.suspicious_agent?(request_to("/api/v1/catalog/terms", "GPTBot/1.1"))).to be(false)
    end

    it "blocks a bot on an app page" do
      expect(described_class.suspicious_agent?(request_to("/admin", "GPTBot/1.1"))).to be(true)
    end

    it "blocks a crawler on an app page" do
      expect(described_class.suspicious_agent?(request_to("/dashboard", "SomeCrawler/2.0"))).to be(true)
    end

    it "blocks a client with no User-Agent on an app page" do
      expect(described_class.suspicious_agent?(request_to("/api/user/email", ""))).to be(true)
    end

    it "does not treat a path that only starts with /docs as docs" do
      expect(described_class::AGENT_READABLE_PATH.call(request_to("/docsx", "GPTBot/1.1"))).to be(false)
    end

    it "lets a bot get the 404 for a path with no route" do
      expect(described_class.suspicious_agent?(request_to("/some-path-that-does-not-exist", "GPTBot/1.1"))).to be(false)
    end

    it "blocks a bot on a page that needs a sign-in" do
      expect(described_class.suspicious_agent?(request_to("/dashboard/settings", "GPTBot/1.1"))).to be(true)
    end

    it "blocks a bot on an unknown API path, which the API catch-all route answers" do
      expect(described_class.suspicious_agent?(request_to("/api/nope", "GPTBot/1.1"))).to be(true)
    end

    [ "Cozi-iCalendar-FeedReader", "Google-Calendar-Importer", "SomeFeedBot/1.0", "" ].each do |user_agent|
      it "lets the calendar app #{user_agent.inspect} fetch the ICS feed" do
        expect(described_class.suspicious_agent?(request_to("/calendar/sample-token", user_agent))).to be(false)
      end
    end

    it "lets Googlebot and browsers read app pages" do
      expect(described_class.suspicious_agent?(request_to("/admin", "Googlebot/2.1"))).to be(false)
      expect(described_class.suspicious_agent?(request_to("/admin", "Mozilla/5.0 (Macintosh)"))).to be(false)
    end
  end

  describe ".unknown_path?" do
    def request_to(path)
      Rack::Attack::Request.new(Rack::MockRequest.env_for(path))
    end

    it "is true for a path with no route" do
      expect(described_class.unknown_path?(request_to("/some-path-that-does-not-exist"))).to be(true)
    end

    it "is false for a path with a route" do
      expect(described_class.unknown_path?(request_to("/admin"))).to be(false)
      expect(described_class.unknown_path?(request_to("/passkey"))).to be(false)
    end
  end

  describe "responses" do
    it "gives a throttled request a typed error body and a Retry-After header" do
      env = Rack::MockRequest.env_for("/api/v1/catalog/terms")
      env["rack.attack.match_data"] = { limit: 300, period: 60, count: 301, epoch_time: 1_000_020 }

      status, headers, body = described_class.throttled_responder.call(Rack::Attack::Request.new(env))

      expect(status).to eq(429)
      expect(headers["retry-after"]).to eq("60")
      expect(JSON.parse(body.join)).to include("code" => "RATE_LIMITED", "retry_after" => 60)
    end

    it "sets Retry-After to the end of the window, not to a whole period" do
      env = Rack::MockRequest.env_for("/calendar/sample-token")
      # 1_000_020 is the start of a 60 s window, so 1_003_590 is 3570 s into an hour window.
      env["rack.attack.match_data"] = { limit: 60, period: 3600, count: 61, epoch_time: 1_003_590 }

      _status, headers, body = described_class.throttled_responder.call(Rack::Attack::Request.new(env))

      expect(headers["retry-after"]).to eq((3600 - (1_003_590 % 3600)).to_s)
      expect(JSON.parse(body.join)["retry_after"]).to eq(3600 - (1_003_590 % 3600))
    end

    it "sends no older RateLimit-Limit, RateLimit-Remaining, or RateLimit-Reset fields" do
      env = Rack::MockRequest.env_for("/api/v1/catalog/terms")
      env["rack.attack.match_data"] = { limit: 300, period: 60, count: 301, epoch_time: 1_000_020 }

      _status, headers, _body = described_class.throttled_responder.call(Rack::Attack::Request.new(env))

      expect(headers.keys.map(&:downcase)).not_to include("ratelimit-limit", "ratelimit-remaining", "ratelimit-reset")
    end

    it "gives a blocked request a typed error body" do
      status, _headers, body = described_class.blocklisted_responder.call(nil)

      expect(status).to eq(403)
      expect(JSON.parse(body.join)).to include("error" => "Forbidden", "code" => "FORBIDDEN")
    end
  end

  describe ".extract_user_id_from_jwt" do
    it "decodes the token once per request, however many rules ask" do
      req = request_with("Bearer #{api_token_for(user)}")
      allow(JsonWebTokenService).to receive(:decode).and_call_original

      3.times { expect(described_class.extract_user_id_from_jwt(req)).to eq(user.id) }

      expect(JsonWebTokenService).to have_received(:decode).once
    end

    it "remembers a bad token as no user, without decoding it again" do
      req = request_with("Bearer not-a-token")
      allow(JsonWebTokenService).to receive(:decode).and_call_original

      2.times { expect(described_class.extract_user_id_from_jwt(req)).to be_nil }

      expect(JsonWebTokenService).to have_received(:decode).once
    end

    it "does not share the answer between requests" do
      other = create(:user)

      expect(described_class.extract_user_id_from_jwt(request_with("Bearer #{api_token_for(user)}"))).to eq(user.id)
      expect(described_class.extract_user_id_from_jwt(request_with("Bearer #{api_token_for(other)}"))).to eq(other.id)
    end
  end

  describe "extension events throttles" do
    def discriminator(name, path)
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for(path, method: "POST", "REMOTE_ADDR" => "1.2.3.4"))
      described_class.throttles.fetch(name).block.call(request)
    end

    it "counts extension events against their own budget" do
      expect(discriminator("api/extension-events", "/api/extension_events")).to eq("1.2.3.4")
      expect(discriminator("api/extension-events", "/api/user/onboard")).to be_nil
    end

    it "does not count extension events against the anonymous API limit that sign-in needs" do
      expect(discriminator("api/ip", "/api/extension_events")).to be_nil
      expect(discriminator("api/ip", "/api/user/onboard")).to eq("1.2.3.4")
    end

    it "counts CSP reports against their own budget, not the anonymous API limit" do
      expect(described_class.throttles.fetch("api/csp-reports")).to have_attributes(limit: 60, period: 60)
      expect(discriminator("api/csp-reports", "/api/csp_reports")).to eq("1.2.3.4")
      expect(discriminator("api/csp-reports", "/api/user/onboard")).to be_nil
      expect(discriminator("api/ip", "/api/csp_reports")).to be_nil
    end
  end

  describe "calendar feed throttles" do
    def discriminator(name, path, ip)
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for(path, "REMOTE_ADDR" => ip))
      described_class.throttles.fetch(name).block.call(request)
    end

    it "limits each feed by a digest of its token, so the cache never stores the token" do
      key = discriminator("calendar/token", "/calendar/sample-token", "1.2.3.4")

      expect(described_class.throttles.fetch("calendar/token")).to have_attributes(limit: 60, period: 3600)
      expect(key).to eq("calendar:#{OpenSSL::Digest::SHA256.hexdigest('sample-token')}")
      expect(key).not_to include("sample-token")
      expect(discriminator("calendar/token", "/dashboard", "1.2.3.4")).to be_nil
    end

    it "gives a feed one budget with or without the .ics suffix" do
      expect(discriminator("calendar/token", "/calendar/sample-token.ics", "1.2.3.4"))
        .to eq(discriminator("calendar/token", "/calendar/sample-token", "1.2.3.4"))
    end

    it "has no limit for each IP address, because calendar apps fetch every feed from a few servers" do
      expect(described_class.throttles.keys.grep(%r{\Acalendar/})).to eq([ "calendar/token" ])
    end

    it "serves many feeds to one IP address without a 429" do
      original_store = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      users = create_list(:user, 3)
      env = { "REMOTE_ADDR" => "5.6.7.8", "HTTP_USER_AGENT" => "Cozi-iCalendar-FeedReader" }

      statuses = Array.new(120) do |i|
        status, _headers, body = Rails.application.call(
          Rack::MockRequest.env_for("/calendar/#{users[i % 3].calendar_token}", **env)
        )
        # Rails.cache keeps a local cache until the body closes.
        body.close if body.respond_to?(:close)
        status
      end

      expect(statuses).to all(eq(200))
    ensure
      Rack::Attack.cache.store = original_store
    end
  end

  describe "meeting link throttles" do
    def discriminator(name, path, method: "GET")
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for(path, method: method, "REMOTE_ADDR" => "1.2.3.4"))
      described_class.throttles.fetch(name).block.call(request)
    end

    it "limits page views of a meeting link by IP address" do
      expect(described_class.throttles.fetch("meet/ip")).to have_attributes(limit: 30, period: 60)
      expect(discriminator("meet/ip", "/meet/sample-token")).to eq("1.2.3.4")
      expect(discriminator("meet/ip", "/meet/sample-token/sign_in")).to eq("1.2.3.4")
      expect(discriminator("meet/ip", "/meeting")).to be_nil
    end

    it "gives picks a tighter budget than page views" do
      expect(described_class.throttles.fetch("meet/pick/ip")).to have_attributes(limit: 5, period: 600)
      expect(discriminator("meet/pick/ip", "/meet/sample-token", method: "POST")).to eq("1.2.3.4")
      expect(discriminator("meet/pick/ip", "/meet/sample-token")).to be_nil
    end

    it "limits one link across IP addresses, with a digest of the token as the key" do
      key = discriminator("meet/token", "/meet/sample-token")

      expect(key).to eq("meet:#{OpenSSL::Digest::SHA256.hexdigest('sample-token')}")
      expect(key).not_to include("sample-token")
    end

    it "answers 429 once a guest uses up the pick budget" do
      original_store = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      env = { "REMOTE_ADDR" => "5.6.7.8", "HTTP_USER_AGENT" => "Mozilla/5.0" }
      app = Rails.application

      statuses = Array.new(6) do
        status, _headers, body = app.call(Rack::MockRequest.env_for("/meet/sample-token", method: "POST", **env))
        # Rails.cache keeps a local cache until the body closes. An open body
        # leaks it into later examples, such as the Risc::Validator spec.
        body.close if body.respond_to?(:close)
        status
      end

      expect(statuses.last).to eq(429)
      expect(statuses.first(5)).to all(satisfy { |status| status != 429 })
    ensure
      # Put back the FailOpenStore from the initializer. Rails.cache alone
      # breaks the "cache store" examples that run after this one.
      Rack::Attack.cache.store = original_store
    end
  end

  describe "cache store" do
    # A store whose database table is missing, as when the cache database
    # exists but solid_cache_entries does not.
    let(:broken_store) do
      Class.new do
        %i[read write increment delete].each do |name|
          define_method(name) { |*| raise ActiveRecord::StatementInvalid, "PG::UndefinedTable" }
        end
      end.new
    end

    let(:app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

    around do |example|
      original = described_class.cache.store
      example.run
    ensure
      described_class.cache.store = original
    end

    it "wraps Rails.cache so a cache error does not stop the request" do
      expect(described_class.cache.store).to be_a(described_class::FailOpenStore)
      expect(described_class.cache.store.__getobj__).to be(Rails.cache)
    end

    it "lets the request through when the cache database raises" do
      described_class.cache.store = described_class::FailOpenStore.new(broken_store)
      allow(Rails.error).to receive(:report)

      status, _headers, _body = described_class.new(app).call(
        Rack::MockRequest.env_for("/api/user/email", "REMOTE_ADDR" => "203.0.113.9")
      )

      expect(status).to eq(200)
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(ActiveRecord::StatementInvalid), hash_including(handled: true)).at_least(:once)
    end

    it "does not hide errors that do not come from the database" do
      store = Class.new { def read(*) = raise(ArgumentError, "bug") }.new

      expect { described_class::FailOpenStore.new(store).read("key") }.to raise_error(ArgumentError)
    end
  end

  describe "process courses throttle" do
    def discriminator(path)
      request = Rack::Attack::Request.new(
        Rack::MockRequest.env_for(path, method: "POST", "HTTP_AUTHORIZATION" => "Bearer #{api_token_for(user)}")
      )
      described_class.throttles.fetch("api/process-courses").block.call(request)
    end

    it "counts single and batch requests against the same budget" do
      expect(discriminator("/api/process_courses")).to eq("process-courses:#{user.id}")
      expect(discriminator("/api/process_courses/batch")).to eq("process-courses:#{user.id}")
    end

    it "counts the path variants that the router also accepts" do
      %w[
        /api/process_courses.json
        /api/process_courses/batch.json
        /api/process_courses/
        /api/process_courses/batch/
        /api//process_courses/batch
      ].each do |path|
        expect(discriminator(path)).to eq("process-courses:#{user.id}"), "expected #{path} to be throttled"
      end
    end

    it "does not count other paths" do
      expect(discriminator("/api/process_courses/other")).to be_nil
      expect(discriminator("/api/courses/reprocess")).to be_nil
    end
  end

  describe "healthcheck safelist" do
    def safelisted?(path)
      described_class.safelists.fetch("allow-healthchecks").matched_by?(
        Rack::Attack::Request.new(Rack::MockRequest.env_for(path))
      )
    end

    it "lets the healthcheck through" do
      expect(safelisted?("/up")).to be(true)
      expect(safelisted?("/up.json")).to be(true)
    end

    it "does not let other paths that start with /up skip the limits" do
      expect(safelisted?("/upload")).to be(false)
      expect(safelisted?("/up/../wp-admin")).to be(false)
    end
  end

  describe "suspicious requests" do
    let(:app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

    around do |example|
      original = described_class.cache.store
      described_class.cache.store = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      described_class.cache.store = original
    end

    def status_for(path)
      described_class.new(app).call(
        Rack::MockRequest.env_for(path, "REMOTE_ADDR" => "203.0.113.20", "HTTP_USER_AGENT" => "Mozilla/5.0")
      ).first
    end

    it "blocks each scanner request" do
      expect(status_for("/wp-admin")).to eq(403)
      expect(status_for("/.env")).to eq(403)
      expect(status_for("/x?file=%2Fetc%2Fpasswd")).to eq(403)
    end

    it "does not ban the IP address, because many students share one campus address" do
      10.times { status_for("/wp-login.php") }

      expect(status_for("/api/v1/catalog/terms")).to eq(200)
    end
  end

  describe "campus address budgets" do
    def discriminator(name, path, method: "GET", headers: {})
      env = Rack::MockRequest.env_for(path, method: method, "REMOTE_ADDR" => "1.2.3.4", **headers)
      described_class.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
    end

    it "counts a request with a valid API token against api/user, not against req/ip" do
      bearer = { "HTTP_AUTHORIZATION" => "Bearer #{api_token_for(user)}" }

      expect(discriminator("req/ip", "/api/user/email", headers: bearer)).to be_nil
      expect(discriminator("api/user", "/api/user/email", headers: bearer)).to eq(user.id)
    end

    it "still counts anonymous requests and bad tokens against req/ip" do
      expect(discriminator("req/ip", "/api/user/email")).to eq("1.2.3.4")
      expect(discriminator("req/ip", "/api/user/email", headers: { "HTTP_AUTHORIZATION" => "Bearer forged" }))
        .to eq("1.2.3.4")
    end

    it "gives sign-in enough room for many students on one address" do
      expect(described_class.throttles.fetch("oauth/callbacks").limit).to be >= 60
      expect(described_class.throttles.fetch("api/ip").limit).to be >= 60
      expect(described_class.throttles.fetch("api/token-mint").limit).to be >= 30
    end

    it "keeps token minting tighter than the general anonymous API limit" do
      expect(described_class.throttles.fetch("api/token-mint").limit)
        .to be < described_class.throttles.fetch("api/ip").limit
    end
  end

  describe "path variants" do
    def discriminator(name, path, headers: {})
      env = Rack::MockRequest.env_for(path, method: "POST", "REMOTE_ADDR" => "1.2.3.4", **headers)
      described_class.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
    end

    it "counts the token-mint path variants that the router also accepts" do
      %w[/api/user/onboard /api/user/onboard.json /api/user/onboard/ /api//user/passkeys/authenticate].each do |path|
        expect(discriminator("api/token-mint", path)).to eq("1.2.3.4"), "expected #{path} to be throttled"
      end
      expect(discriminator("api/token-mint", "/api/user/onboarding")).to be_nil
    end

    it "counts the preview path variants that the router also accepts" do
      bearer = { "HTTP_AUTHORIZATION" => "Bearer #{api_token_for(user)}" }

      %w[/api/calendar_preferences/preview /api/calendar_preferences/preview.json].each do |path|
        expect(discriminator("api/preview-template", path, headers: bearer)).to eq("preview:#{user.id}")
      end
    end
  end

  describe "admin throttles" do
    def discriminator(name, session: {}, method: "GET", path: "/admin/users")
      env = Rack::MockRequest.env_for(path, method: method, "REMOTE_ADDR" => "1.2.3.4")
      env["rack.session"] = session
      described_class.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
    end

    it "keys on the signed-in user, which stays the same while the cookie value changes" do
      session = { "warden.user.user.key" => [ [ user.id ], "salt" ] }

      expect(discriminator("admin/session", session: session)).to eq("user:#{user.id}")
      expect(discriminator("admin/destructive", session: session, method: "DELETE")).to eq("user:#{user.id}")
    end

    it "keys on the IP address when no one is signed in" do
      expect(discriminator("admin/session")).to eq("ip:1.2.3.4")
    end
  end

  describe ".semantic_search_throttled?" do
    around do |example|
      original = described_class.cache.store
      described_class.cache.store = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      described_class.cache.store = original
    end

    def env_for(path, ip: "203.0.113.30")
      Rack::MockRequest.env_for(path, method: "POST", "REMOTE_ADDR" => ip)
    end

    it "shares the catalog/semantic budget between GraphQL and REST" do
      throttle = described_class.throttles.fetch("catalog/semantic")
      rest_env = -> { Rack::MockRequest.env_for("/api/v1/catalog/sections?q=x&semantic=true", "REMOTE_ADDR" => "203.0.113.30") }
      (throttle.limit - 1).times { throttle.matched_by?(Rack::Attack::Request.new(rest_env.call)) }

      expect(described_class.semantic_search_throttled?(env_for("/api/v1/graphql"))).to be(false)
      expect(described_class.semantic_search_throttled?(env_for("/api/v1/graphql"))).to be(true)
    end

    it "puts the throttle data on the request for the RateLimit fields" do
      env = env_for("/api/v1/graphql")
      described_class.semantic_search_throttled?(env)

      expect(env["rack.attack.throttle_data"]).to include("catalog/semantic")
    end

    it "counts nothing for a GraphQL request that runs no semantic search" do
      request = Rack::Attack::Request.new(env_for("/api/v1/graphql"))

      expect(described_class.throttles.fetch("catalog/semantic").block.call(request)).to be_nil
    end
  end
end
