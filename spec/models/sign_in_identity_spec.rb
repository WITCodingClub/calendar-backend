# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: sign_in_identities
#
#  id                :bigint           not null, primary key
#  email             :string           not null
#  last_signed_in_at :datetime
#  provider          :string           not null
#  uid               :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  tenant_id         :string           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_sign_in_identities_on_provider_and_tenant_id_and_uid  (provider,tenant_id,uid) UNIQUE
#  index_sign_in_identities_on_user_id                         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
