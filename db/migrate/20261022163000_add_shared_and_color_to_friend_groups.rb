# frozen_string_literal: true

# A shared friend group shows to its members too, read only (extension#213).
# A group can also have a color. Each member chooses how a shared group
# treats them: active, hidden from their own list, or opted out.
#
# friend_group_opt_outs keeps an opt-out when the owner removes the member
# and adds them again, because that makes a new membership row.
class AddSharedAndColorToFriendGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :friend_groups, :shared, :boolean, default: false, null: false
    add_column :friend_groups, :color, :string
    add_column :friend_group_memberships, :status, :string, default: "active", null: false

    create_table :friend_group_opt_outs do |t|
      t.references :friend_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :friend_group_opt_outs, %i[friend_group_id user_id], unique: true
  end
end
