# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::MetadataDocumentClient do
  let(:url) { "https://client.example/oauth/metadata.json" }
  let(:document) { { "client_id" => url, "client_name" => "Example", "redirect_uris" => [ "https://client.example/cb" ] } }

  before { allow(Resolv).to receive(:getaddresses).with("client.example").and_return([ "93.184.215.14" ]) }

  def fetch(target = url) = described_class.new.fetch(URI(target))

  it "fetches the JSON document" do
    stub_request(:get, url).to_return(status: 200, body: document.to_json, headers: { "Content-Type" => "application/json" })

    expect(fetch).to eq(document)
  end

  it "refuses a URL that is not https on port 443" do
    expect { fetch("http://client.example/m.json") }.to raise_error(described_class::FetchError, /https on port 443/)
    expect { fetch("https://client.example:8443/m.json") }.to raise_error(described_class::FetchError, /https on port 443/)
  end

  it "refuses a host that resolves to a private address" do
    allow(Resolv).to receive(:getaddresses).with("client.example").and_return([ "93.184.215.14", "10.0.0.5" ])

    expect { fetch }.to raise_error(described_class::FetchError, /not a public address/)
  end

  it "refuses a host that does not resolve" do
    allow(Resolv).to receive(:getaddresses).with("client.example").and_return([])

    expect { fetch }.to raise_error(described_class::FetchError, /does not resolve/)
  end

  it "refuses a redirect or an error status" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "https://other.example/" })

    expect { fetch }.to raise_error(described_class::FetchError, /answered 302/)
  end

  it "refuses a body over the size limit" do
    stub_request(:get, url).to_return(status: 200, body: "x" * (described_class::MAX_BYTES + 1))

    expect { fetch }.to raise_error(described_class::FetchError, /larger than/)
  end

  it "refuses a body that is not a JSON object" do
    stub_request(:get, url).to_return(status: 200, body: "[1]")
    expect { fetch }.to raise_error(described_class::FetchError, /not a JSON object/)

    stub_request(:get, url).to_return(status: 200, body: "{")
    expect { fetch }.to raise_error(described_class::FetchError, /not valid JSON/)
  end

  it "turns a timeout into a fetch error" do
    stub_request(:get, url).to_timeout

    expect { fetch }.to raise_error(described_class::FetchError, /could not fetch/)
  end

  describe ".blocked?" do
    %w[127.0.0.1 10.1.2.3 172.16.0.1 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 ::1 fd00::1 fe80::1 ::ffff:127.0.0.1 nonsense].each do |address|
      it "blocks #{address}" do
        expect(described_class.blocked?(address)).to be(true)
      end
    end

    %w[93.184.215.14 2606:2800:21f:cb07:6820:80da:af6b:8b2c].each do |address|
      it "allows #{address}" do
        expect(described_class.blocked?(address)).to be(false)
      end
    end
  end
end
