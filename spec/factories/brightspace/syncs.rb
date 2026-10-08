# frozen_string_literal: true

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
FactoryBot.define do
  factory :brightspace_sync, class: "Brightspace::Sync" do
    association :connection, factory: :brightspace_connection
    snapshot_id { SecureRandom.uuid }
    payload_digest { Digest::SHA256.hexdigest(snapshot_id) }
    collected_at { Time.current }
    status { "complete" }
  end
end
