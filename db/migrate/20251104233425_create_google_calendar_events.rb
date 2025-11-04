class CreateGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :google_calendar_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :meeting_time, null: true, foreign_key: true
      t.string :google_event_id, null: false
      t.string :calendar_id, null: false
      t.string :summary
      t.string :location
      t.datetime :start_time
      t.datetime :end_time
      t.text :recurrence

      t.timestamps
    end

    # Add indexes for faster lookups
    add_index :google_calendar_events, :google_event_id
    add_index :google_calendar_events, [:user_id, :calendar_id]
    add_index :google_calendar_events, [:user_id, :meeting_time_id], unique: true
  end
end
