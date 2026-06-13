class CreateGoogleCalendars < ActiveRecord::Migration[8.1]
  def change
    create_table :google_calendars do |t|
      t.references :oauth_credential, null: false, foreign_key: true
      t.string :google_calendar_id, null: false
      t.string :summary
      t.text :description
      t.string :time_zone
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :google_calendars, :google_calendar_id, unique: true
    add_index :google_calendars, :last_synced_at
  end
end
