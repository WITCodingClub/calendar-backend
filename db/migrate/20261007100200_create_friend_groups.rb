# frozen_string_literal: true

# Named groups of friends, for example "study group" or "roommates". A group
# belongs to one user and only that user sees it.
#
# A membership points at the friendship, not at the friend's user row. When the
# friendship goes, the database removes its memberships too (on_delete:
# :cascade), so a group never holds someone who is no longer a friend.
class CreateFriendGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :friend_groups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :friend_groups, "user_id, lower(name)", unique: true, name: "index_friend_groups_on_user_id_and_lower_name"

    create_table :friend_group_memberships do |t|
      t.references :friend_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :friendship, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :friend_group_memberships, %i[friend_group_id friendship_id], unique: true,
                                         name: "index_friend_group_memberships_on_group_and_friendship"
  end
end
