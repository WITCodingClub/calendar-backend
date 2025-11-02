class AddEmailToOauthCredentials < ActiveRecord::Migration[8.1]
  def up
    # Remove old unique index on (user_id, provider)
    remove_index :oauth_credentials, column: [:user_id, :provider], unique: true, if_exists: true

    # Add email column
    add_column :oauth_credentials, :email, :string

    # Add new unique index on (user_id, provider, email) concurrently
    safety_assured do
      add_index :oauth_credentials, [:user_id, :provider, :email],
                unique: true,
                name: 'index_oauth_credentials_on_user_provider_email'
    end
  end

  def down
    remove_index :oauth_credentials, name: 'index_oauth_credentials_on_user_provider_email', if_exists: true
    remove_column :oauth_credentials, :email
    add_index :oauth_credentials, [:user_id, :provider], unique: true
  end
end
