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
      expect(headers["Retry-After"]).to eq("60")
      expect(JSON.parse(body.join)).to include("code" => "RATE_LIMITED", "retry_after" => 60)
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
  end
end
