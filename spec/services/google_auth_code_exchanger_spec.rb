# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleAuthCodeExchanger do
  let(:args) do
    { code: "auth-code", code_verifier: "verifier", redirect_uri: "https://ext.chromiumapp.org/" }
  end

  def stub_google(status:, body:)
    response = instance_double(Faraday::Response, success?: status < 400, body: body, status: status)
    connection = instance_double(Faraday::Connection)
    allow(connection).to receive(:post).and_return(response)
    allow(Faraday).to receive(:new).and_return(connection)
    connection
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_EXTENSION_CLIENT_ID").and_return("ext-client")
    allow(ENV).to receive(:[]).with("GOOGLE_EXTENSION_CLIENT_SECRET").and_return("ext-secret")
  end

  it "returns the access token Google hands back" do
    stub_google(status: 200, body: { "access_token" => "ya29.token" })

    result = described_class.exchange(**args)

    expect(result).to be_success
    expect(result.access_token).to eq("ya29.token")
  end

  it "sends the secret, which is the whole reason the exchange happens here" do
    connection = stub_google(status: 200, body: { "access_token" => "ya29.token" })
    captured = nil
    request = instance_double(Faraday::Request, headers: {})
    allow(request).to receive(:body=) { |value| captured = value }
    allow(connection).to receive(:post).and_yield(request).and_return(
      instance_double(Faraday::Response, success?: true, body: { "access_token" => "ya29.token" }, status: 200)
    )

    described_class.exchange(**args)

    expect(captured).to include("client_secret=ext-secret")
    expect(captured).to include("code_verifier=verifier")
  end

  it "fails when Google refuses the exchange" do
    stub_google(status: 400, body: { "error" => "invalid_grant", "error_description" => "Code was already redeemed." })

    result = described_class.exchange(**args)

    expect(result).not_to be_success
    expect(result.error).to include("invalid_grant")
  end

  it "fails when Google returns no token" do
    stub_google(status: 200, body: {})

    result = described_class.exchange(**args)

    expect(result).not_to be_success
  end

  it "refuses to call Google without every part of the exchange" do
    expect(described_class.exchange(**args, code: "")).not_to be_success
    expect(described_class.exchange(**args, code_verifier: nil)).not_to be_success
    expect(described_class.exchange(**args, redirect_uri: "")).not_to be_success
  end

  it "reports a network failure rather than raising" do
    connection = instance_double(Faraday::Connection)
    allow(connection).to receive(:post).and_raise(Faraday::ConnectionFailed, "boom")
    allow(Faraday).to receive(:new).and_return(connection)

    result = described_class.exchange(**args)

    expect(result).not_to be_success
    expect(result.error).to include("token exchange failed")
  end
end
