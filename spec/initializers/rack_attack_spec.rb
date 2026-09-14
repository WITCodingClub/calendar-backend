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
      expect(described_class.suspicious_agent?(request_to("/docsx", "GPTBot/1.1"))).to be(true)
    end

    it "lets Googlebot and browsers read app pages" do
      expect(described_class.suspicious_agent?(request_to("/admin", "Googlebot/2.1"))).to be(false)
      expect(described_class.suspicious_agent?(request_to("/admin", "Mozilla/5.0 (Macintosh)"))).to be(false)
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
end
