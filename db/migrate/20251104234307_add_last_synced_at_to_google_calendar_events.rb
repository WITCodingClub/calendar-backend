class AddLastSyncedAtToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :google_calendar_events, :last_synced_at, :datetime
    add_column :google_calendar_events, :event_data_hash, :string
  end
end
