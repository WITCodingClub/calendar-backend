# frozen_string_literal: true

require "rails_helper"

RSpec.describe JsonWebTokenService do
  let(:payload) { { user_id: 42, role: "user" } }

  describe ".encode" do
    it "returns a non-empty JWT string" do
      token = described_class.encode(payload)
      expect(token).to be_a(String)
      expect(token).not_to be_empty
    end

    it "encodes an expiration claim by default" do
      token = described_class.encode(payload)
      decoded = JWT.decode(token, described_class::SECRET_KEY, true, algorithm: "HS256")[0]
      expect(decoded["exp"]).to be_present
    end

    it "uses the provided expiration time" do
      exp = 1.hour.from_now
      token = described_class.encode(payload, exp)
      decoded = JWT.decode(token, described_class::SECRET_KEY, true, algorithm: "HS256")[0]
      expect(decoded["exp"]).to be_within(2).of(exp.to_i)
    end

    it "omits the exp claim when exp is nil" do
      token = described_class.encode(payload, nil)
      decoded = JWT.decode(token, described_class::SECRET_KEY, true, algorithm: "HS256")[0]
      expect(decoded["exp"]).to be_nil
    end
  end

  describe ".decode" do
    it "decodes a valid token and returns a HashWithIndifferentAccess" do
      token = described_class.encode(payload)
      result = described_class.decode(token)

      expect(result).to be_a(ActiveSupport::HashWithIndifferentAccess)
      expect(result[:user_id]).to eq(42)
      expect(result[:role]).to eq("user")
    end

    it "returns nil for a tampered token" do
      token = "#{described_class.encode(payload)}tampered"
      expect(described_class.decode(token)).to be_nil
    end

    it "returns nil for a completely invalid token" do
      expect(described_class.decode("not.a.valid.token")).to be_nil
    end

    it "returns nil for an expired token" do
      token = described_class.encode(payload, 1.second.ago)
      expect(described_class.decode(token)).to be_nil
    end

    it "decodes a token with no expiration claim" do
      token = described_class.encode(payload, nil)
      result = described_class.decode(token)
      expect(result[:user_id]).to eq(42)
    end
  end

  describe "round-trip encode/decode" do
    it "preserves all payload keys after encode and decode" do
      token = described_class.encode(payload)
      result = described_class.decode(token)

      expect(result[:user_id]).to eq(payload[:user_id])
      expect(result[:role]).to eq(payload[:role])
    end
  end
end
