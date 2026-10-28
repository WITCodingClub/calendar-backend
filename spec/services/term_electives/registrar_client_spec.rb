# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermElectives::RegistrarClient do
  subject(:client) { described_class.new }

  let(:url) { "https://wit.edu/sites/default/files/2031-01/SCDS_Electives.pdf" }

  it "returns the body as binary and sends the bot user agent" do
    stub_request(:get, url).with(headers: { "User-Agent" => "WITCalendarBot/1.0" }).to_return(status: 200, body: "%PDF-1.7")

    body = client.get(url)

    expect(body).to eq("%PDF-1.7")
    expect(body.encoding).to eq(Encoding::BINARY)
  end

  it "returns nil for a missing file" do
    stub_request(:get, url).to_return(status: 404)

    expect(client.get(url)).to be_nil
  end

  it "follows a redirect on wit.edu" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/sites/default/files/new.pdf" })
    stub_request(:get, "https://wit.edu/sites/default/files/new.pdf").to_return(status: 200, body: "moved")

    expect(client.get(url)).to eq("moved")
  end

  it "refuses a redirect to another host" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "https://example.com/a.pdf" })

    expect { client.get(url) }.to raise_error(TermElectives::FetchError, /not allowed/)
  end

  it "stops after a few redirects" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => url })

    expect { client.get(url) }.to raise_error(TermElectives::FetchError, /too many redirects/)
  end

  it "raises a fetch error for a server error" do
    stub_request(:get, url).to_return(status: 500)

    expect { client.get(url) }.to raise_error(TermElectives::FetchError, /HTTP 500/)
  end

  it "raises a fetch error when the connection fails" do
    stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("refused"))

    expect { client.get(url) }.to raise_error(TermElectives::FetchError, /refused/)
  end
end
