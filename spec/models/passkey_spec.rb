# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkey, type: :model do
  subject { create(:passkey) }

  it { is_expected.to belong_to(:user) }

  it { is_expected.to validate_presence_of(:external_id) }
  it { is_expected.to validate_uniqueness_of(:external_id) }
  it { is_expected.to validate_presence_of(:public_key) }
  it { is_expected.to validate_presence_of(:nickname) }
  it { is_expected.to validate_length_of(:nickname).is_at_most(60) }
  it { is_expected.to validate_uniqueness_of(:nickname).scoped_to(:user_id).case_insensitive }
end
