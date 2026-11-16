# frozen_string_literal: true

require "rails_helper"

RSpec.describe HttpFetcher do
  let(:error) { Class.new(StandardError) }
  let(:fetcher) { described_class.new(allowed_hosts: [ "example.edu" ], error: error) }
  let(:url) { "https://example.edu/page" }

  it "sends the bot user agent and returns the body as bytes" do
    stub_request(:get, url).with(headers: { "User-Agent" => described_class::USER_AGENT }).to_return(status: 200, body: "ok")

    expect(fetcher.get(url)).to eq("ok".b)
  end

  it "raises the error class of the caller" do
    stub_request(:get, url).to_return(status: 500)

    expect { fetcher.get(url) }.to raise_error(error, /HTTP 500/)
  end

  it "calls before_request with each URL, also after a redirect" do
    seen = []
    paced = described_class.new(allowed_hosts: [ "example.edu" ], error: error, before_request: ->(u) { seen << u })
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/moved" })
    stub_request(:get, "https://example.edu/moved").to_return(status: 200, body: "ok")

    paced.get(url)

    expect(seen).to eq([ url, "https://example.edu/moved" ])
  end

  it "builds a connection with the retry policy and the user agent" do
    connection = described_class.connection

    expect(connection.builder.handlers).to include(Faraday::Retry::Middleware)
    expect(connection.headers["User-Agent"]).to eq(described_class::USER_AGENT)
  end
end
