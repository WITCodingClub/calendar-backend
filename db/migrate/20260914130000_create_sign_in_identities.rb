# frozen_string_literal: true

class CreateSignInIdentities < ActiveRecord::Migration[8.1]
  def change
    # An outside account that can sign a person in. It holds no tokens: a
    # sign-in needs only the verified id, and calendar tokens stay in
    # oauth_credentials.
    create_table :sign_in_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      # Microsoft: the Entra tenant id (tid) and object id (oid). Together they
      # are stable. The email can change, so it is never the key.
      t.string :tenant_id, null: false
      t.string :uid, null: false
      t.string :email, null: false
      t.datetime :last_signed_in_at

      t.timestamps
    end

    add_index :sign_in_identities, [ :provider, :tenant_id, :uid ], unique: true
  end
end
