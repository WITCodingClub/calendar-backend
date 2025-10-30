class AddGoogleOauthFieldsToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :google_uid, :string
    add_column :users, :google_access_token, :string
    add_column :users, :google_refresh_token, :string
    add_column :users, :google_token_expires_at, :datetime
    add_index :users, :google_uid, algorithm: :concurrently
  end
end
