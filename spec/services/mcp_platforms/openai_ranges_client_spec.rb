# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpPlatforms::OpenaiRangesClient do
  let(:url) { described_class::URL }

  def stub_body(body, status: 200)
    stub_request(:get, url).to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "returns the IPv4 and IPv6 ranges" do
    stub_body(file_fixture("openai/chatgpt_connectors.json").read)

    expect(described_class.new.fetch).to eq([ "203.0.113.0/28", "198.51.100.7/32", "2001:db8:10::/48" ])
  end

  it "refuses an error status" do
    stub_body("", status: 503)

    expect { described_class.new.fetch }.to raise_error(described_class::Error, /answered 503/)
  end

  it "refuses an empty list" do
    stub_body({ prefixes: [] }.to_json)

    expect { described_class.new.fetch }.to raise_error(described_class::Error, /no prefixes/)
  end

  it "refuses a range that is too wide or invalid" do
    stub_body({ prefixes: [ { ipv4Prefix: "0.0.0.0/0" } ] }.to_json)
    expect { described_class.new.fetch }.to raise_error(described_class::Error, /too wide/)

    stub_body({ prefixes: [ { ipv6Prefix: "2001:db8::/16" } ] }.to_json)
    expect { described_class.new.fetch }.to raise_error(described_class::Error, /too wide/)

    stub_body({ prefixes: [ { ipv4Prefix: "not-an-ip" } ] }.to_json)
    expect { described_class.new.fetch }.to raise_error(described_class::Error, /invalid range/)
  end

  it "turns a network failure into an error" do
    stub_request(:get, url).to_timeout

    expect { described_class.new.fetch }.to raise_error(described_class::Error, /could not fetch/)
  end
end
