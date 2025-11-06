class CreateGoogleCalendarTables < ActiveRecord::Migration[8.1]
  def change
    # Create google_calendars table
    create_table :google_calendars do |t|
      t.string :google_calendar_id, null: false
      t.string :summary
      t.text :description
      t.string :time_zone
      t.datetime :last_synced_at
      t.references :oauth_credential, null: false, foreign_key: true

      t.timestamps
    end
    add_index :google_calendars, :google_calendar_id, unique: true

    # Create google_calendar_events table
    create_table :google_calendar_events do |t|
      t.references :google_calendar, null: false, foreign_key: true
      t.references :meeting_time, null: true, foreign_key: true
      t.string :google_event_id, null: false
      t.string :summary
      t.string :location
      t.datetime :start_time
      t.datetime :end_time
      t.text :recurrence
      t.datetime :last_synced_at
      t.string :event_data_hash

      t.timestamps
    end

    # Add indexes for faster lookups
    add_index :google_calendar_events, :google_event_id
    add_index :google_calendar_events, [:google_calendar_id, :meeting_time_id]
  end
end
