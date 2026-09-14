# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: oauth_credentials
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
#  email            :string
#  metadata         :jsonb
#  provider         :string           not null
#  refresh_token    :string
#  token_expires_at :datetime
#  uid              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_oauth_credentials_on_provider_and_uid     (provider,uid) UNIQUE
#  index_oauth_credentials_on_token_expires_at     (token_expires_at)
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe OauthCredential, type: :model do
  subject { create(:oauth_credential) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_one(:course_calendar).dependent(:destroy) }
  it { is_expected.to have_many(:security_events).dependent(:nullify) }

  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_inclusion_of(:provider).in_array(%w[google microsoft]) }
  it { is_expected.to validate_presence_of(:uid) }
  it { is_expected.to validate_uniqueness_of(:uid).scoped_to(:provider) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:email) }

  describe "disconnecting a Google account" do
    let(:user) { create(:user) }
    let(:calendar_id) { "synthetic-course-calendar" }
    let!(:owner) do
      create(:oauth_credential, user: user, email: "owner@example.test",
                                access_token: "synthetic-owner-token",
                                refresh_token: "synthetic-owner-refresh",
                                token_expires_at: 1.hour.from_now)
    end
    let!(:second) do
      create(:oauth_credential, user: user, email: "second@example.test",
                                access_token: "synthetic-second-token",
                                refresh_token: "synthetic-second-refresh",
                                token_expires_at: 1.hour.from_now)
    end

    before do
      # The course calendar belongs to one credential and is shared with every
      # Google account the person connects.
      create(:course_calendar, oauth_credential: owner, external_calendar_id: calendar_id)
      stub_google_service_account
      stub_request(:delete, google_acl_url(calendar_id, "owner@example.test")).to_return(status: 204)
      stub_request(:delete, google_acl_url(calendar_id, "second@example.test")).to_return(status: 204)
      stub_request(:delete, google_calendar_list_url(calendar_id)).to_return(status: 204)
    end

    def list_removal_with(token)
      a_request(:delete, google_calendar_list_url(calendar_id)).with(headers: { "Authorization" => "Bearer #{token}" })
    end

    it "removes the course calendar from the list of the account that owns it, before the calendar row is gone" do
      owner.destroy!

      expect(list_removal_with("synthetic-owner-token")).to have_been_made.once
    end

    it "removes the course calendar from the list of an account that does not own it" do
      second.destroy!

      expect(list_removal_with("synthetic-second-token")).to have_been_made.once
    end

    it "stops sharing the course calendar with the disconnected account" do
      second.destroy!

      expect(a_request(:delete, google_acl_url(calendar_id, "second@example.test"))).to have_been_made.once
      expect(a_request(:delete, google_acl_url(calendar_id, "owner@example.test"))).not_to have_been_made
    end

    it "does not hide an error that is not a Google API failure" do
      allow(GoogleCalendarService).to receive(:new).and_raise(NoMethodError, "undefined method for synthetic test")

      expect { owner.destroy! }.to raise_error(NoMethodError)
    end

    it "still disconnects the account when Google refuses its token" do
      stub_request(:delete, google_calendar_list_url(calendar_id))
        .to_return(status: 401, body: file_fixture("google_calendar/unauthorized.json").read,
                   headers: { "Content-Type" => "application/json" })

      expect { second.destroy! }.not_to raise_error
      expect(described_class.exists?(second.id)).to be(false)
      expect(a_request(:delete, google_acl_url(calendar_id, "second@example.test"))).to have_been_made.once
    end
  end

  # No matcher covers what an after_destroy callback does to other records, so
  # these examples check the sessions directly.
  describe "sessions after a Google account is disconnected" do
    let(:user) { create(:user) }
    # The factory gives the credential the user's own email: the WIT account
    # that onboarding verified.
    let!(:sign_in_account) { create(:oauth_credential, user: user) }
    let!(:personal_account) { create(:oauth_credential, user: user, email: "personal@example.test") }

    def session_for(token)
      UserSession.find_by(jti: JsonWebTokenService.decode(token)[:jti])
    end

    it "keeps the sessions when the account only shares the calendar" do
      token = api_token_for(user)

      personal_account.destroy!

      expect(session_for(token).reload).to be_active
    end

    it "ends the Google sign-in sessions when the sign-in account is disconnected" do
      token = api_token_for(user)

      sign_in_account.destroy!

      expect(session_for(token).reload).to be_revoked
    end

    it "keeps the passkey sessions, which the Google account did not open" do
      token = api_token_for(user, source: "passkey", passkey: create(:passkey, user: user))

      sign_in_account.destroy!

      expect(session_for(token).reload).to be_active
    end
  end

  describe "the revoked flag" do
    let(:credential) do
      create(:oauth_credential, refresh_token: "synthetic-refresh-token",
                                metadata: { "token_revoked" => true,
                                            "token_revoked_at" => 1.day.ago.iso8601,
                                            "revocation_reason" => "invalid_grant" })
    end

    # RefreshOauthTokensJob sets the flag. A new access token comes only from a
    # working grant, so a reconnect or a refresh must clear it.
    it "clears once a new access token is saved" do
      credential.update!(access_token: "synthetic-new-access-token")

      expect(credential.reload).not_to be_token_revoked
      expect(credential).not_to be_needs_reauth
    end

    it "stays when only the metadata changes" do
      credential.update!(metadata: credential.metadata.merge("note" => "synthetic"))

      expect(credential.reload).to be_token_revoked
    end
  end
end
