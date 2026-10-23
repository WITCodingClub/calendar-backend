# frozen_string_literal: true

# A shared friend group shows to its members too, read only (extension#213).
# A group can also have a color. Each member chooses how a shared group
# treats them: active, hidden from their own list, or opted out.
class AddSharedAndColorToFriendGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :friend_groups, :shared, :boolean, default: false, null: false
    add_column :friend_groups, :color, :string
    add_column :friend_group_memberships, :status, :string, default: "active", null: false
  end
end
