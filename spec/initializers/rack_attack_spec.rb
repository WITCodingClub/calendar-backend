# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rack::Attack do
  let(:user) { User.create!(email: "ratelimit@wit.edu", password: "password123") }

  def request_with(header)
    Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/user/email", "HTTP_AUTHORIZATION" => header))
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
      other = User.create!(email: "other-ratelimit@wit.edu", password: "password123")

      expect(described_class.extract_user_id_from_jwt(request_with("Bearer #{api_token_for(user)}"))).to eq(user.id)
      expect(described_class.extract_user_id_from_jwt(request_with("Bearer #{api_token_for(other)}"))).to eq(other.id)
    end
  end
end
