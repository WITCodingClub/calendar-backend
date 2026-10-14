# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpPlatforms::RefreshOpenaiRangesJob do
  it "stores the ranges for McpPlatforms" do
    allow(McpPlatforms).to receive(:store_openai_ranges)
    stub_request(:get, McpPlatforms::OpenaiRangesClient::URL)
      .to_return(status: 200, body: file_fixture("openai/chatgpt_connectors.json").read, headers: { "Content-Type" => "application/json" })

    described_class.perform_now

    expect(McpPlatforms).to have_received(:store_openai_ranges).with([ "203.0.113.0/28", "198.51.100.7/32", "2001:db8:10::/48" ])
  end

  it "keeps the old copy when the fetch fails" do
    allow(McpPlatforms).to receive(:store_openai_ranges)
    stub_request(:get, McpPlatforms::OpenaiRangesClient::URL).to_return(status: 500)

    expect { described_class.perform_now }.to raise_error(McpPlatforms::OpenaiRangesClient::Error)
    expect(McpPlatforms).not_to have_received(:store_openai_ranges)
  end
end
