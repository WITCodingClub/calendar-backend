class CreateOauthCredentials < ActiveRecord::Migration[8.1]
  def up
    create_table :oauth_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :access_token, null: false
      t.string :refresh_token
      t.datetime :token_expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :oauth_credentials, [:provider, :uid], unique: true
    add_index :oauth_credentials, [:user_id, :provider], unique: true

    # Migrate existing Google credentials from users table
    User.reset_column_information
    User.find_each do |user|
      next if user.google_uid.blank?

      metadata = {}
      metadata["course_calendar_id"] = user.google_course_calendar_id if user.google_course_calendar_id.present?

      OauthCredential.create!(
        user_id: user.id,
        provider: "google",
        uid: user.google_uid,
        access_token: user.google_access_token,
        refresh_token: user.google_refresh_token,
        token_expires_at: user.google_token_expires_at,
        metadata: metadata
      )
    end

    # Remove Google columns from users table
    safety_assured do
      remove_column :users, :google_uid
      remove_column :users, :google_access_token
      remove_column :users, :google_refresh_token
      remove_column :users, :google_token_expires_at
      remove_column :users, :google_course_calendar_id
    end
  end

  def down
    # Add Google columns back to users table
    add_column :users, :google_uid, :string
    add_column :users, :google_access_token, :string
    add_column :users, :google_refresh_token, :string
    add_column :users, :google_token_expires_at, :datetime
    add_column :users, :google_course_calendar_id, :string

    # Migrate Google credentials back to users table
    OauthCredential.reset_column_information
    OauthCredential.where(provider: "google").find_each do |credential|
      user = User.find(credential.user_id)
      user.update!(
        google_uid: credential.uid,
        google_access_token: credential.access_token,
        google_refresh_token: credential.refresh_token,
        google_token_expires_at: credential.token_expires_at,
        google_course_calendar_id: credential.metadata&.dig("course_calendar_id")
      )
    end

    # Drop oauth_credentials table
    drop_table :oauth_credentials
  end
end
