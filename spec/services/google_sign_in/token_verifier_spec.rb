# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleSignIn::TokenVerifier do
  let(:client_id) { "wit-calendar.apps.googleusercontent.com" }

  def stub_tokeninfo(status:, body:)
    allow(GoogleCalendar).to receive(:client_ids).and_return([ client_id ])
    stub_request(:get, described_class::TOKENINFO_URL).with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
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
