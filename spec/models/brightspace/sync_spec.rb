# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_syncs
#
#  id             :bigint           not null, primary key
#  collected_at   :datetime         not null
#  payload_digest :string           not null
#  result         :jsonb            not null
#  status         :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  connection_id  :bigint           not null
#  snapshot_id    :string           not null
#
# Indexes
#
#  index_brightspace_syncs_on_connection_id                  (connection_id)
#  index_brightspace_syncs_on_connection_id_and_snapshot_id  (connection_id,snapshot_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connection_id => brightspace_connections.id)
#
RSpec.describe Brightspace::Sync, type: :model do
  subject { create(:brightspace_sync) }

  it { is_expected.to belong_to(:connection) }
  it { is_expected.to validate_presence_of(:snapshot_id) }
  it { is_expected.to validate_length_of(:snapshot_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:snapshot_id).scoped_to(:connection_id) }
  it { is_expected.to validate_presence_of(:payload_digest) }
  it { is_expected.to validate_presence_of(:collected_at) }
  it { is_expected.to validate_inclusion_of(:status).in_array(%w[complete]) }
end
