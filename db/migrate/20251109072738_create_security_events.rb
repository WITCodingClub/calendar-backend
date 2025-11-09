class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      # JWT ID for deduplication (unique identifier for the event)
      t.string :jti, null: false

      # Event type (e.g., "account-disabled", "sessions-revoked")
      t.string :event_type, null: false

      # Google Account ID (sub claim from the JWT)
      t.string :google_subject, null: false

      # Associated user (nullable in case we can't find the user)
      t.references :user, null: true, foreign_key: true

      # Associated OAuth credential (nullable, only for token-specific events)
      t.references :oauth_credential, null: true, foreign_key: true

      # Event reason (e.g., "hijacking", "bulk-account")
      t.string :reason

      # Raw event data (encrypted for security)
      t.text :raw_event_data

      # Processing state
      t.boolean :processed, default: false, null: false
      t.datetime :processed_at

      # Error tracking
      t.text :processing_error

      # Retention policy tracking
      t.datetime :expires_at

      t.timestamps
    end

    # Index for deduplication
    add_index :security_events, :jti, unique: true

    # Index for finding unprocessed events
    add_index :security_events, :processed

    # Index for finding events by type
    add_index :security_events, :event_type

    # Index for cleanup/retention
    add_index :security_events, :expires_at
  end
end
