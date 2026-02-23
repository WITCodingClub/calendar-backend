# frozen_string_literal: true

class CreateFriendships < ActiveRecord::Migration[8.1]
  def change
    create_table :friendships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :addressee, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    # Prevent duplicate requests (in either direction)
    add_index :friendships, [:requester_id, :addressee_id], unique: true

    # Composite indexes for efficient friend queries
    add_index :friendships, [:requester_id, :status]
    add_index :friendships, [:addressee_id, :status]
  end

end
