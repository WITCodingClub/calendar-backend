# frozen_string_literal: true

require "rails_helper"

RSpec.describe JsonWebTokenService do
  it "always sets an expiry claim" do
    token   = described_class.encode({ user_id: 1 })
    payload = JWT.decode(token, described_class::SECRET_KEY, true, algorithm: "HS256")[0]

    expect(payload["exp"]).to be_present
  end

  it "raises when asked to encode without an expiry" do
    expect { described_class.encode({ user_id: 1 }, nil) }.to raise_error(ArgumentError)
  end

  it "does not mutate the caller's payload hash" do
    payload = { user_id: 1 }
    described_class.encode(payload)

    expect(payload).not_to have_key(:exp)
  end

  it "round-trips a valid token" do
    token = described_class.encode({ user_id: 42 })

    expect(described_class.decode(token)[:user_id]).to eq(42)
  end

  it "returns nil for an expired token" do
    token = described_class.encode({ user_id: 42 }, 1.hour.ago)

    expect(described_class.decode(token)).to be_nil
  end

  it "returns nil for a token signed with the wrong key" do
    forged = JWT.encode({ user_id: 999, exp: 1.day.from_now.to_i }, "not-the-real-secret")

    expect(described_class.decode(forged)).to be_nil
  end
end
