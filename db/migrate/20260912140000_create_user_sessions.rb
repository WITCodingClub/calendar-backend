# frozen_string_literal: true

class CreateUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      # The jti claim of the token this row stands for. A token is only good
      # while its row says so, which is what makes revocation possible at all.
      t.string :jti, null: false
      t.string :source, null: false
      t.references :passkey, foreign_key: true

      t.string :user_agent
      t.string :device_label
      t.string :ip_address

      t.datetime :last_seen_at
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :revoked_reason

      t.timestamps
    end

    add_index :user_sessions, :jti, unique: true
    add_index :user_sessions, [ :user_id, :revoked_at ]
    add_index :user_sessions, :expires_at
  end
end
