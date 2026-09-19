# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: passkeys
#
#  id           :bigint           not null, primary key
#  last_used_at :datetime
#  nickname     :string           not null
#  public_key   :string           not null
#  sign_count   :bigint           default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  external_id  :string           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_passkeys_on_external_id           (external_id) UNIQUE
#  index_passkeys_on_user_id               (user_id)
#  index_passkeys_on_user_id_and_nickname  (user_id,nickname) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
