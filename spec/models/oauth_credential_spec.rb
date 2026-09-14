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
end
