class CreateFriendships < ActiveRecord::Migration[8.1]
  def change
    create_table :friendships do |t|
      t.bigint :requester_id, null: false
      t.bigint :addressee_id, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    add_index :friendships, :requester_id
    add_index :friendships, :addressee_id
    add_index :friendships, [ :requester_id, :addressee_id ], unique: true
    add_index :friendships, [ :requester_id, :status ]
    add_index :friendships, [ :addressee_id, :status ]
    add_foreign_key :friendships, :users, column: :requester_id
    add_foreign_key :friendships, :users, column: :addressee_id
  end
end
