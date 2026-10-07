# frozen_string_literal: true

# Each side of a friendship sets how much of its own schedule the other side
# can see. 0 is "full", the behavior before this column existed.
class AddVisibilityToFriendships < ActiveRecord::Migration[8.1]
  def change
    add_column :friendships, :requester_visibility, :integer, null: false, default: 0
    add_column :friendships, :addressee_visibility, :integer, null: false, default: 0
  end
end
