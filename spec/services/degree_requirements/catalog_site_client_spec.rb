# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CatalogSiteClient do
  subject(:client) { described_class.new(delay: 0, wayback_delay: 0) }

  let(:url) { "https://catalog.wit.edu/programs-az/" }

  it "returns the page body as UTF-8" do
    stub_request(:get, url).to_return(status: 200, body: "<p>caf\xC3\xA9</p>".b)

    expect(client.get(url)).to eq("<p>café</p>")
  end

  it "sends the bot user agent" do
    stub_request(:get, url).with(headers: { "User-Agent" => "WITCalendarBot/1.0" }).to_return(status: 200, body: "ok")

    expect(client.get(url)).to eq("ok")
  end

  it "returns nil for a missing page" do
    stub_request(:get, url).to_return(status: 404)

    expect(client.get(url)).to be_nil
  end

  it "follows a redirect" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/programs-az/new/" })
    stub_request(:get, "https://catalog.wit.edu/programs-az/new/").to_return(status: 200, body: "moved")

    expect(client.get(url)).to eq("moved")
  end

  it "stops after a few redirects" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => url })

    expect { client.get(url) }.to raise_error(DegreeRequirements::FetchError, /too many redirects/)
  end

  it "raises a fetch error for a server error" do
    stub_request(:get, url).to_return(status: 500)

    expect { client.get(url) }.to raise_error(DegreeRequirements::FetchError, /HTTP 500/)
  end

  it "raises a fetch error when the connection fails" do
    stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("refused"))

    expect { client.get(url) }.to raise_error(DegreeRequirements::FetchError, /refused/)
  end

  it "waits longer between Wayback Machine requests" do
    site_pacer = instance_double(DegreeRequirements::RequestPacer, wait: nil)
    wayback_pacer = instance_double(DegreeRequirements::RequestPacer, wait: nil)
    allow(DegreeRequirements::RequestPacer).to receive(:new).with(0.5).and_return(site_pacer)
    allow(DegreeRequirements::RequestPacer).to receive(:new).with(5).and_return(wayback_pacer)
    stub_request(:get, /.*/).to_return(status: 200, body: "ok")

    paced = described_class.new
    paced.get(url)
    paced.get("https://web.archive.org/web/2026id_/#{url}")

    expect(site_pacer).to have_received(:wait).once
    expect(wayback_pacer).to have_received(:wait).once
  end
end
