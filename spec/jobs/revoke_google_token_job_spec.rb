# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeGoogleTokenJob do
  def stub_revoke(status:, body: "{}")
    stub_request(:post, google_revoke_url)
      .with(body: { "token" => "synthetic-refresh-token" })
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "asks Google to revoke the token" do
    revoke = stub_revoke(status: 200)

    described_class.perform_now("synthetic-refresh-token")

    expect(revoke).to have_been_requested.once
  end

  it "treats a token that Google already revoked as done" do
    stub_revoke(status: 400, body: file_fixture("google_oauth/revoke_invalid_token.json").read)

    expect { described_class.perform_now("synthetic-refresh-token") }.not_to have_enqueued_job(described_class)
  end

  it "retries when Google does not confirm the revocation, so that the failure is not only a log line" do
    stub_revoke(status: 503, body: file_fixture("google_oauth/revoke_server_error.json").read)

    expect { described_class.perform_now("synthetic-refresh-token") }
      .to have_enqueued_job(described_class).with("synthetic-refresh-token")
  end

  it "does nothing without a token" do
    described_class.perform_now(nil)

    expect(a_request(:post, google_revoke_url)).not_to have_been_made
  end

  it "keeps the token out of the job logs" do
    expect(described_class.log_arguments?).to be(false)
  end
end
