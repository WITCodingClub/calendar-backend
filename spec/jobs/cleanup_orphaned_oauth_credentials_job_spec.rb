# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupOrphanedOauthCredentialsJob do
  let(:user) { create(:user) }
  # An access token that expired, and no refresh token to get a new one.
  let!(:expired) { create(:oauth_credential, user: user, token_expires_at: 1.day.ago, refresh_token: nil) }

  it "marks a credential that can no longer reach Google as needing sign-in again, and keeps it" do
    described_class.perform_now

    expect(OauthCredential.exists?(expired.id)).to be(true)
    expect(expired.reload).to be_token_revoked
    expect(expired).to be_needs_reauth
  end

  it "keeps the course calendar and the sessions" do
    calendar = create(:course_calendar, oauth_credential: expired)
    token = api_token_for(user)

    described_class.perform_now

    expect(CourseCalendar.exists?(calendar.id)).to be(true)
    expect(UserSession.find_by(jti: JsonWebTokenService.decode(token)[:jti])).to be_active
  end

  it "does not ask Google to revoke an access token that already expired" do
    described_class.perform_now

    expect(a_request(:post, google_revoke_url)).not_to have_been_made
  end

  it "leaves a credential that can still refresh its token alone" do
    refreshable = create(:oauth_credential, token_expires_at: 1.day.ago, refresh_token: "synthetic-refresh-token")

    described_class.perform_now

    expect(refreshable.reload).not_to be_token_revoked
  end
end
