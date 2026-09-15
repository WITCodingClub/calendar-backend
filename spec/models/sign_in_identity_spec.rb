# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInIdentity, type: :model do
  subject { create(:sign_in_identity) }

  it { is_expected.to belong_to(:user) }

  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_inclusion_of(:provider).in_array(%w[microsoft]) }
  it { is_expected.to validate_presence_of(:tenant_id) }
  it { is_expected.to validate_presence_of(:uid) }
  it { is_expected.to validate_uniqueness_of(:uid).scoped_to(:provider, :tenant_id) }
  it { is_expected.to validate_presence_of(:email) }

  describe "#record_sign_in!" do
    it "stores the current email and the sign-in time" do
      subject.record_sign_in!(email: "renamed.student@wit.edu")

      expect(subject.reload).to have_attributes(email: "renamed.student@wit.edu", last_signed_in_at: be_present)
    end
  end

  # A removed identity must not end sessions that Google or a passkey opened.
  # No matcher covers a missing callback, so this checks the sessions directly.
  it "keeps the user's sessions when it is destroyed" do
    session = create(:user_session, user: subject.user)

    subject.destroy!

    expect(session.reload).to be_active
  end
end
