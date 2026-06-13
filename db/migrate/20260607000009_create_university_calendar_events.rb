class CreateUniversityCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :university_calendar_events do |t|
      t.references :term, foreign_key: true
      t.string :ics_uid, null: false
      t.text :summary, null: false
      t.text :description
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.boolean :all_day, default: false, null: false
      t.string :category
      t.string :location
      t.string :organization
      t.string :academic_term
      t.string :event_type_raw
      t.string :source_url
      t.text :recurrence
      t.datetime :last_fetched_at
      t.timestamps
    end

    add_index :university_calendar_events, :ics_uid, unique: true
    add_index :university_calendar_events, :category
    add_index :university_calendar_events, :academic_term
    add_index :university_calendar_events, [ :start_time, :end_time ]
  end
end
