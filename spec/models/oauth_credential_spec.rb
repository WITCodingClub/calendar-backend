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
end
