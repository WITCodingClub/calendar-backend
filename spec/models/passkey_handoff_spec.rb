# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: passkey_handoffs
#
#  id          :bigint           not null, primary key
#  code_digest :string           not null
#  expires_at  :datetime         not null
#  purpose     :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_passkey_handoffs_on_code_digest  (code_digest) UNIQUE
#  index_passkey_handoffs_on_expires_at   (expires_at)
#  index_passkey_handoffs_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe PasskeyHandoff, type: :model do
  subject { create(:passkey_handoff) }

  it { is_expected.to belong_to(:user) }

  it { is_expected.to validate_presence_of(:code_digest) }
  it { is_expected.to validate_uniqueness_of(:code_digest) }
  it { is_expected.to validate_presence_of(:purpose) }
  it { is_expected.to validate_inclusion_of(:purpose).in_array(%w[register session]) }
  it { is_expected.to validate_presence_of(:expires_at) }
end
