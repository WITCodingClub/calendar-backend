# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentials::SignedState do
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  it "gives back the claims of a state of the same purpose" do
    state = described_class.generate(purpose: "a", ttl: 5.minutes, user_id: 7)

    expect(described_class.verify(state, purpose: "a")).to include("user_id" => 7, "purpose" => "a")
  end

  it "refuses a state of another purpose" do
    state = described_class.generate(purpose: "a", ttl: 5.minutes, user_id: 7)

    expect(described_class.verify(state, purpose: "b")).to be_nil
  end

  it "refuses an expired state" do
    state = described_class.generate(purpose: "a", ttl: -1.minute, user_id: 7)

    expect(described_class.verify(state, purpose: "a")).to be_nil
  end

  it "lets a one-use state be consumed once" do
    state = described_class.generate(purpose: "a", ttl: 5.minutes, once_key: "spec_state", user_id: 7)

    expect(described_class.consume(state, purpose: "a", once_key: "spec_state")).to include("user_id" => 7)
    expect(described_class.consume(state, purpose: "a", once_key: "spec_state")).to be_nil
  end
end
