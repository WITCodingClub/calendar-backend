# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: user_sessions
#
#  id             :bigint           not null, primary key
#  device_label   :string
#  expires_at     :datetime         not null
#  ip_address     :string
#  jti            :string           not null
#  last_seen_at   :datetime
#  revoked_at     :datetime
#  revoked_reason :string
#  source         :string           not null
#  user_agent     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  passkey_id     :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_sessions_on_expires_at              (expires_at)
#  index_user_sessions_on_jti                     (jti) UNIQUE
#  index_user_sessions_on_passkey_id              (passkey_id)
#  index_user_sessions_on_user_id                 (user_id)
#  index_user_sessions_on_user_id_and_revoked_at  (user_id,revoked_at)
#
# Foreign Keys
#
#  fk_rails_...  (passkey_id => passkeys.id)
#  fk_rails_...  (user_id => users.id)
#
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
