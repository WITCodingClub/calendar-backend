# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Disconnecting an OAuth credential through the API", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:personal_account) do
    create(:oauth_credential, user: user, email: "personal@example.test",
                              access_token: "synthetic-access-token",
                              refresh_token: "synthetic-refresh-token")
  end

  before do
    # The API refuses to disconnect the last credential.
    create(:oauth_credential, user: user)
  end

  it "revokes the Google grant with the refresh token after the credential is gone" do
    stub_request(:post, google_revoke_url).to_return(status: 200, body: "{}")
    headers = auth_headers_for(user)

    perform_enqueued_jobs do
      delete "/api/user/oauth_credentials/#{personal_account.public_id}", headers: headers
    end

    expect(response).to have_http_status(:ok)
    expect(OauthCredential.exists?(personal_account.id)).to be(false)
    expect(a_request(:post, google_revoke_url).with(body: { "token" => "synthetic-refresh-token" })).to have_been_made.once
  end

  it "answers without waiting for Google, and leaves the revoke to a job" do
    delete "/api/user/oauth_credentials/#{personal_account.public_id}", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(a_request(:post, google_revoke_url)).not_to have_been_made
    expect(enqueued_jobs.map { |job| job["job_class"] }).to include("RevokeGoogleTokenJob")
  end
end
