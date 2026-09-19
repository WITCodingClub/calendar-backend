# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeOauthCredentialJob do
  include ActiveJob::TestHelper

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
    create(:course_calendar, oauth_credential: credential, external_calendar_id: calendar_id)
    stub_google_service_account
    stub_request(:delete, google_acl_url(calendar_id, "revoked@example.test")).to_return(status: 204)
    stub_request(:delete, google_calendar_list_url(calendar_id)).to_return do
      google_calls << :calendar_list
      { status: 204 }
    end
    stub_request(:post, google_revoke_url).to_return do
      google_calls << :revoke
      { status: 200, body: "{}" }
    end
  end

  def perform_with_revocation
    perform_enqueued_jobs(only: RevokeGoogleTokenJob) { described_class.perform_now(credential.id) }
  end

  it "removes the course calendar while the token still works, and revokes the token after" do
    perform_with_revocation

    expect(google_calls).to eq([ :calendar_list, :revoke ])
    expect(OauthCredential.exists?(credential.id)).to be(false)
  end

  it "revokes the refresh token, so that the whole grant ends and not only an access token that may have expired" do
    perform_with_revocation

    expect(a_request(:post, google_revoke_url).with(body: { "token" => "synthetic-refresh-token" })).to have_been_made.once
  end
end
