class CreateGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :google_calendar_events do |t|
      t.references :google_calendar, null: false, foreign_key: true
      t.bigint :meeting_time_id
      t.bigint :final_exam_id
      t.bigint :university_calendar_event_id
      t.string :google_event_id, null: false
      t.string :summary
      t.string :location
      t.text :recurrence
      t.datetime :start_time
      t.datetime :end_time
      t.string :event_data_hash
      t.jsonb :user_edited_fields
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :google_calendar_events, :google_event_id
    add_index :google_calendar_events, :meeting_time_id
    add_index :google_calendar_events, :final_exam_id
    add_index :google_calendar_events, :university_calendar_event_id
    add_index :google_calendar_events, :last_synced_at
    add_index :google_calendar_events, [ :google_calendar_id, :meeting_time_id ],
              name: "idx_on_google_calendar_id_meeting_time_id"
    add_index :google_calendar_events, [ :google_calendar_id, :final_exam_id ],
              unique: true, where: "final_exam_id IS NOT NULL",
              name: "idx_gcal_events_unique_final_exam"
    add_index :google_calendar_events, [ :google_calendar_id, :meeting_time_id ],
              unique: true, where: "meeting_time_id IS NOT NULL",
              name: "idx_gcal_events_unique_meeting_time"
    add_index :google_calendar_events, [ :google_calendar_id, :university_calendar_event_id ],
              unique: true, where: "university_calendar_event_id IS NOT NULL",
              name: "idx_gcal_events_unique_university"

    add_foreign_key :google_calendar_events, :course_meeting_times, column: :meeting_time_id
  end
end
