# frozen_string_literal: true

# One snapshot that the extension sent. The stored result answers a repeat of
# the same snapshot, and the digest catches a snapshot id sent again with
# other data.
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
module Brightspace
  class Sync < ApplicationRecord
    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :bss, min_hash_length: 12

    belongs_to :connection, class_name: "Brightspace::Connection", inverse_of: :syncs

    validates :snapshot_id, presence: true, length: { maximum: 64 }, uniqueness: { scope: :connection_id }
    validates :payload_digest, presence: true
    validates :collected_at, presence: true
    validates :status, inclusion: { in: %w[complete] }
  end
end
