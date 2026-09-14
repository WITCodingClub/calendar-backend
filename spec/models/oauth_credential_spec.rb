# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredential, type: :model do
  subject { create(:oauth_credential) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_one(:google_calendar).dependent(:destroy) }
  it { is_expected.to have_many(:security_events).dependent(:nullify) }

  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_inclusion_of(:provider).in_array(%w[google]) }
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
      create(:google_calendar, oauth_credential: owner, google_calendar_id: calendar_id)
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
