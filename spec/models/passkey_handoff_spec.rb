# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasskeyHandoff, type: :model do
  subject { create(:passkey_handoff) }

  it { is_expected.to belong_to(:user) }

  it { is_expected.to validate_presence_of(:code_digest) }
  it { is_expected.to validate_uniqueness_of(:code_digest) }
  it { is_expected.to validate_presence_of(:purpose) }
  it { is_expected.to validate_inclusion_of(:purpose).in_array(%w[register session]) }
  it { is_expected.to validate_presence_of(:expires_at) }
end
