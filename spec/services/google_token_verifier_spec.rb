# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleTokenVerifier do
  let(:client_id) { "wit-calendar.apps.googleusercontent.com" }

  def stub_tokeninfo(status:, body:)
    response = instance_double(Faraday::Response, success?: status == 200, status: status, body: body)
    connection = instance_double(Faraday::Connection, get: response)
    allow_any_instance_of(described_class).to receive(:connection).and_return(connection)
    allow_any_instance_of(described_class).to receive(:allowed_client_ids).and_return([ client_id ])
  end

  it "fails when no token is provided" do
    expect(described_class.verify_access_token("").success?).to be(false)
  end

  it "returns the normalized email for a token issued to our client" do
    stub_tokeninfo(status: 200, body: { "aud" => client_id, "email" => "Student@WIT.edu", "email_verified" => "true" })

    result = described_class.verify_access_token("valid-token")

    expect(result.success?).to be(true)
    expect(result.email).to eq("student@wit.edu")
  end

  it "rejects a token minted for a different OAuth client (audience mismatch)" do
    stub_tokeninfo(status: 200, body: { "aud" => "some-other-app", "email" => "student@wit.edu" })

    expect(described_class.verify_access_token("replayed-token").success?).to be(false)
  end

  it "rejects a token Google did not accept" do
    stub_tokeninfo(status: 401, body: { "error" => "invalid_token" })

    expect(described_class.verify_access_token("bad-token").success?).to be(false)
  end

  it "rejects a token with the right audience but no email" do
    stub_tokeninfo(status: 200, body: { "aud" => client_id })

    expect(described_class.verify_access_token("no-email").success?).to be(false)
  end
end
