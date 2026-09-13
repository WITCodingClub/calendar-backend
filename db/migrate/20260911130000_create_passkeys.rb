# frozen_string_literal: true

class CreatePasskeys < ActiveRecord::Migration[8.1]
  def change
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      # The credential id the authenticator returns, Base64-url encoded.
      t.string :external_id, null: false
      t.string :public_key,  null: false
      t.string :nickname,    null: false
      t.bigint :sign_count,  null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :passkeys, :external_id, unique: true
    add_index :passkeys, [ :user_id, :nickname ], unique: true

    # A WebAuthn challenge is single use and short lived. It lives in the
    # database rather than the cache because the API runs across several
    # processes, and because consuming a row is what makes the single use
    # guarantee enforceable.
    create_table :webauthn_challenges do |t|
      t.references :user, foreign_key: true
      t.string :handle,    null: false
      t.string :challenge, null: false
      t.string :purpose,   null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :webauthn_challenges, :handle, unique: true
    add_index :webauthn_challenges, :expires_at
  end
end
