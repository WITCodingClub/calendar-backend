# frozen_string_literal: true

require "rails_helper"

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

  # No matcher covers a conditional after_destroy callback, so these examples
  # check its effect on the person's sessions.
  describe "sessions after destroy" do
    def active_sessions(user)
      UserSession.where(user_id: user.id, revoked_at: nil)
    end

    it "ends the sessions when a Google credential is destroyed" do
      credential = create(:oauth_credential)
      api_token_for(credential.user)

      expect { credential.destroy! }.to change { active_sessions(credential.user).count }.from(1).to(0)
    end

    it "keeps the sessions when a Microsoft credential is destroyed" do
      credential = create(:oauth_credential, :microsoft)
      api_token_for(credential.user)

      expect { credential.destroy! }.not_to(change { active_sessions(credential.user).count })
    end
  end
  describe "disconnecting a Microsoft credential", :microsoft_graph do
    let(:credential) { create(:oauth_credential, :microsoft, token_expires_at: 1.hour.from_now) }
    let(:calendar_url) { "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1" }

    before { create(:course_calendar, :microsoft, oauth_credential: credential, external_calendar_id: "AAMkSyntheticCalendar1") }

    it "deletes the Outlook calendar with the token before the rows are gone" do
      rows_at_delete = nil
      delete = stub_request(:delete, calendar_url).to_return do
        rows_at_delete = [ OauthCredential.exists?(credential.id), CourseCalendar.exists?(oauth_credential_id: credential.id) ]
        { status: 204 }
      end

      expect { credential.destroy! }.not_to have_enqueued_job(MicrosoftGraphCalendarDeleteJob)

      expect(delete).to have_been_requested
      expect(rows_at_delete).to eq([ true, true ])
      expect(CourseCalendar.exists?(oauth_credential_id: credential.id)).to be(false)
    end

    it "still disconnects when Graph fails" do
      stub_request(:delete, calendar_url).to_return(status: 503, body: "{}")

      expect { credential.destroy! }.not_to raise_error

      expect(OauthCredential.exists?(credential.id)).to be(false)
    end

    it "still disconnects when Microsoft refuses the refresh token" do
      credential.update!(token_expires_at: 1.hour.ago)
      stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL).to_return(graph_json_response("token_invalid_grant", status: 400))

      expect { credential.destroy! }.not_to raise_error

      expect(OauthCredential.exists?(credential.id)).to be(false)
      expect(a_request(:delete, calendar_url)).not_to have_been_made
    end
  end

  describe "disconnecting a Google credential" do
    it "does not call Microsoft Graph" do
      credential = create(:oauth_credential)

      credential.destroy!

      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
