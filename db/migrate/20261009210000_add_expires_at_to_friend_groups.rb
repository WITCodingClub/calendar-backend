# frozen_string_literal: true

# An optional end date for a friend group (#707). When it passes, the group is
# removed. The friendships in it stay.
class AddExpiresAtToFriendGroups < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :friend_groups, :expires_at, :datetime
    add_index :friend_groups, :expires_at, where: "expires_at IS NOT NULL", algorithm: :concurrently
  end
end
