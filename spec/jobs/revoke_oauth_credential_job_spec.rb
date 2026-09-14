# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeOauthCredentialJob do
  let(:user) { create(:user) }
  let(:calendar_id) { "synthetic-course-calendar" }
  let(:google_calls) { [] }
  let!(:credential) do
    create(:oauth_credential, user: user, email: "revoked@example.test",
                              access_token: "synthetic-access-token",
                              refresh_token: "synthetic-refresh-token",
                              token_expires_at: 1.hour.from_now)
  end

  before do
    create(:google_calendar, oauth_credential: credential, google_calendar_id: calendar_id)
    stub_google_service_account
    stub_request(:delete, google_acl_url(calendar_id, "revoked@example.test")).to_return(status: 204)
    stub_request(:delete, google_calendar_list_url(calendar_id)).to_return do
      google_calls << :calendar_list
      { status: 204 }
    end
  end

  def stub_revoke(status: 200, body: "{}")
    stub_request(:post, google_revoke_url).to_return do
      google_calls << :revoke
      { status: status, body: body, headers: { "Content-Type" => "application/json" } }
    end
  end

  it "removes the course calendar while the token still works, and revokes the token after" do
    stub_revoke

    described_class.perform_now(credential.id)

    expect(google_calls).to eq([ :calendar_list, :revoke ])
    expect(OauthCredential.exists?(credential.id)).to be(false)
  end

  it "revokes the refresh token, so that the whole grant ends and not only an access token that may have expired" do
    stub_revoke

    described_class.perform_now(credential.id)

    expect(a_request(:post, google_revoke_url).with(body: { "token" => "synthetic-refresh-token" })).to have_been_made.once
  end

  it "fails the job when Google does not confirm the revocation, so that the failure is not only a log line" do
    stub_revoke(status: 503, body: file_fixture("google_oauth/revoke_server_error.json").read)

    expect { described_class.perform_now(credential.id) }
      .to raise_error(RevokeOauthCredentialJob::RevocationFailed, /HTTP 503/)
  end

  it "treats a token that Google already revoked as done" do
    stub_revoke(status: 400, body: file_fixture("google_oauth/revoke_invalid_token.json").read)

    expect { described_class.perform_now(credential.id) }.not_to raise_error
    expect(OauthCredential.exists?(credential.id)).to be(false)
  end
end
