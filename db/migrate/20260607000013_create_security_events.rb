class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      t.references :user, foreign_key: true
      t.references :oauth_credential, foreign_key: true
      t.string :event_type, null: false
      t.string :google_subject, null: false
      t.string :jti, null: false
      t.string :reason
      t.text :raw_event_data
      t.boolean :processed, default: false, null: false
      t.datetime :processed_at
      t.text :processing_error
      t.datetime :expires_at
      t.timestamps
    end

    add_index :security_events, :jti, unique: true
    add_index :security_events, :event_type
    add_index :security_events, :processed
    add_index :security_events, :expires_at
  end
end
