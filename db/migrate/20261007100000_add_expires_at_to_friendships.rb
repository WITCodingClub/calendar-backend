# frozen_string_literal: true

class AddExpiresAtToFriendships < ActiveRecord::Migration[8.1]
  def change
    add_column :friendships, :expires_at, :datetime
    add_index :friendships, :expires_at, where: "expires_at IS NOT NULL"

    # A later end date, or a permanent friendship, needs the consent of both
    # users. One user proposes it and the other accepts it. proposed_by_id is
    # set only while a proposal is open. The proposal is then either a date
    # (proposed_expires_at) or permanent (proposed_permanent), never both.
    add_column :friendships, :proposed_expires_at, :datetime
    add_column :friendships, :proposed_permanent, :boolean, default: false, null: false
    add_reference :friendships, :proposed_by, foreign_key: { to_table: :users }, index: true

    add_check_constraint :friendships,
                         "(proposed_by_id IS NULL AND proposed_expires_at IS NULL AND proposed_permanent = false) OR " \
                         "(proposed_by_id IS NOT NULL AND ((proposed_expires_at IS NULL) = proposed_permanent))",
                         name: "friendships_expiry_proposal_shape"
  end
end
