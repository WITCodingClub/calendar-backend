class CreateOauthCredentials < ActiveRecord::Migration[8.1]
  def up
    create_table :oauth_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.string :access_token, null: false
      t.string :refresh_token
      t.datetime :token_expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :oauth_credentials, [:provider, :uid], unique: true
    add_index :oauth_credentials, [:user_id, :provider, :email],
              unique: true,
              name: 'index_oauth_credentials_on_user_provider_email'
  end

  def down
    drop_table :oauth_credentials
  end
end
