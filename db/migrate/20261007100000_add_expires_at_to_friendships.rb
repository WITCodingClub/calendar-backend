# frozen_string_literal: true

class AddExpiresAtToFriendships < ActiveRecord::Migration[8.1]
  def change
    add_column :friendships, :expires_at, :datetime
    add_index :friendships, :expires_at, where: "expires_at IS NOT NULL"
  end
end
