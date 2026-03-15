# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauthStateService do
  describe ".generate_state" do
    it "returns a non-empty JWT string" do
      state = described_class.generate_state(user_id: 1, email: "user@example.com")
      expect(state).to be_a(String)
      expect(state.split(".").length).to eq(3) # JWT has 3 parts
    end

    it "encodes the user_id and email in the state" do
      state = described_class.generate_state(user_id: 42, email: "test@example.com")
      decoded = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256")[0]

      expect(decoded["user_id"]).to eq(42)
      expect(decoded["email"]).to eq("test@example.com")
    end

    it "includes a nonce for replay attack prevention" do
      state1 = described_class.generate_state(user_id: 1, email: "user@example.com")
      state2 = described_class.generate_state(user_id: 1, email: "user@example.com")

      decoded1 = JWT.decode(state1, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
      decoded2 = JWT.decode(state2, Rails.application.secret_key_base, true, algorithm: "HS256")[0]

      expect(decoded1["nonce"]).not_to eq(decoded2["nonce"])
    end

    it "includes an expiration claim" do
      state = described_class.generate_state(user_id: 1, email: "user@example.com")
      decoded = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256")[0]

      expect(decoded["exp"]).to be_present
      expect(decoded["exp"]).to be > Time.current.to_i
    end
  end

  describe ".verify_state" do
    it "returns a hash with user_id and email for a valid state" do
      state = described_class.generate_state(user_id: 42, email: "test@example.com")
      result = described_class.verify_state(state)

      expect(result["user_id"]).to eq(42)
      expect(result["email"]).to eq("test@example.com")
    end

    it "returns nil for a tampered state" do
      state = "#{described_class.generate_state(user_id: 1, email: "a@b.com")}tampered"
      expect(described_class.verify_state(state)).to be_nil
    end

    it "returns nil for an expired state" do
      travel_to(2.hours.ago) do
        @state = described_class.generate_state(user_id: 1, email: "test@example.com")
      end
      expect(described_class.verify_state(@state)).to be_nil
    end

    it "returns nil for a completely invalid string" do
      expect(described_class.verify_state("not-a-jwt")).to be_nil
    end
  end
end
