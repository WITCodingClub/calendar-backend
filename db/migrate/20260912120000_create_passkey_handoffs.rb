# frozen_string_literal: true

class CreatePasskeyHandoffs < ActiveRecord::Migration[8.1]
  def change
    create_table :passkey_handoffs do |t|
      t.references :user, null: false, foreign_key: true
      # SHA-256 of the code. The code itself is a bearer credential, so it is
      # never stored: a leaked database should not hand anyone a live session.
      t.string :code_digest, null: false
      t.string :purpose,     null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :passkey_handoffs, :code_digest, unique: true
    add_index :passkey_handoffs, :expires_at
  end
end
