# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpPlatforms do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    described_class.reset!
  end

  after { described_class.reset! }

  it "knows Anthropic's outbound range" do
    expect(described_class.include?("160.79.104.1")).to be(true)
    expect(described_class.include?("160.79.112.1")).to be(false)
  end

  it "knows the OpenAI ranges once the job stores them" do
    expect(described_class.include?("203.0.113.5")).to be(false)

    described_class.store_openai_ranges([ "203.0.113.0/28", "2001:db8:10::/48" ])

    expect(described_class.include?("203.0.113.5")).to be(true)
    expect(described_class.include?("2001:db8:10::1")).to be(true)
  end

  it "reads the cache again after the memo expires" do
    described_class.include?("1.1.1.1")
    cache.write(described_class::OPENAI_CACHE_KEY, [ "203.0.113.0/28" ])

    expect(described_class.include?("203.0.113.5")).to be(false)
    travel(described_class::MEMO_TTL + 1.second) { expect(described_class.include?("203.0.113.5")).to be(true) }
  end

  # Another thread can call reset! between the freshness check and the return.
  # The stub runs reset! at that point, in the middle of the call.
  it "still answers when reset! runs during the call" do
    described_class.include?("1.1.1.1")
    allow(described_class::MEMO_TTL).to receive(:ago) do
      described_class.reset!
      1.hour.ago
    end

    expect(described_class.include?("160.79.104.1")).to be(true)
  end

  it "is false for a blank or invalid address" do
    expect(described_class.include?(nil)).to be(false)
    expect(described_class.include?("nonsense")).to be(false)
  end
end
