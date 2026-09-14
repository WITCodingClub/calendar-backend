# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserSession, type: :model do
  subject { create(:user_session) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:passkey).optional }

  it { is_expected.to validate_presence_of(:jti) }
  it { is_expected.to validate_uniqueness_of(:jti) }
  it { is_expected.to validate_presence_of(:source) }
  it { is_expected.to validate_inclusion_of(:source).in_array(%w[google_onboard passkey]) }
  it { is_expected.to validate_presence_of(:expires_at) }
end
