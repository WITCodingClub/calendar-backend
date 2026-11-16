# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risc::StreamClient do
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:key_file) do
    Tempfile.new([ "service_account", ".json" ]).tap do |file|
      file.write({ client_email: "robot@example.iam.gserviceaccount.com", private_key: rsa_key.to_pem,
                   private_key_id: "key-1" }.to_json)
      file.flush
    end
  end
  let(:client) { described_class.new(key_path: key_file.path) }

  after { key_file.close! }

  def signed_by_service_account?(request)
    token = request.headers["Authorization"].delete_prefix("Bearer ")
    payload, header = JWT.decode(token, rsa_key.public_key, true, algorithm: "RS256")
    payload["aud"] == described_class::TOKEN_AUDIENCE && header["kid"] == "key-1"
  end

  it "subscribes the receiver to every security event type" do
    stub = stub_request(:post, "https://risc.googleapis.com/v1beta/stream:update").with do |request|
      body = JSON.parse(request.body)
      signed_by_service_account?(request) &&
        body["delivery"]["url"] == "https://calendar.example/risc/events" &&
        body["events_requested"] == SecurityEvent::ALL_EVENT_TYPES
    end

    client.configure("https://calendar.example/risc/events")

    expect(stub).to have_been_requested
  end

  it "reads the stream configuration" do
    stub_request(:get, "https://risc.googleapis.com/v1beta/stream")
      .to_return(status: 200, body: { delivery: { url: "https://calendar.example/risc/events" } }.to_json)

    expect(client.stream.dig("delivery", "url")).to eq("https://calendar.example/risc/events")
  end

  it "raises an Error with the status when Google refuses" do
    stub_request(:post, "https://risc.googleapis.com/v1beta/stream/status:update")
      .to_return(status: 403, body: "denied")

    expect { client.update_status("enabled") }.to raise_error(described_class::Error, /403/)
  end

  it "raises an Error when the key file is missing" do
    expect { described_class.new(key_path: "/nonexistent/key.json") }.to raise_error(described_class::Error, /not found/)
  end
end
