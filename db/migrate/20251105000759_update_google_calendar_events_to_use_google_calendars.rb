class UpdateGoogleCalendarEventsToUseGoogleCalendars < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Add new reference column without foreign key
    add_reference :google_calendar_events, :google_calendar, null: true, index: { algorithm: :concurrently }

    # Migrate existing data
    # Group events by calendar_id and user_id to create GoogleCalendar records
    safety_assured do
      execute <<-SQL
        INSERT INTO google_calendars (google_calendar_id, oauth_credential_id, created_at, updated_at, last_synced_at)
        SELECT DISTINCT
          gce.calendar_id,
          oc.id as oauth_credential_id,
          NOW(),
          NOW(),
          MAX(gce.last_synced_at)
        FROM google_calendar_events gce
        INNER JOIN oauth_credentials oc ON gce.user_id = oc.user_id
        WHERE oc.metadata->>'course_calendar_id' = gce.calendar_id
        GROUP BY gce.calendar_id, oc.id
        ON CONFLICT (google_calendar_id) DO NOTHING
      SQL

      # Update google_calendar_events to reference the new google_calendars
      execute <<-SQL
        UPDATE google_calendar_events gce
        SET google_calendar_id = gc.id
        FROM google_calendars gc
        WHERE gc.google_calendar_id = gce.calendar_id
      SQL
    end

    # Make the new column non-nullable
    safety_assured { change_column_null :google_calendar_events, :google_calendar_id, false }

    # Remove old indexes that reference calendar_id
    remove_index :google_calendar_events, name: "index_google_calendar_events_on_user_id_and_calendar_id", if_exists: true

    # Remove old calendar_id column
    safety_assured { remove_column :google_calendar_events, :calendar_id }

    # Add new index
    add_index :google_calendar_events, [:google_calendar_id, :meeting_time_id], algorithm: :concurrently
  end

  def down
    # Add back calendar_id column
    add_column :google_calendar_events, :calendar_id, :string, null: false

    # Restore data
    safety_assured do
      execute <<-SQL
        UPDATE google_calendar_events gce
        SET calendar_id = gc.google_calendar_id
        FROM google_calendars gc
        WHERE gce.google_calendar_id = gc.id
      SQL
    end

    # Remove new index
    remove_index :google_calendar_events, column: [:google_calendar_id, :meeting_time_id], if_exists: true

    # Add back old index
    add_index :google_calendar_events, [:user_id, :calendar_id]

    # Remove reference column
    remove_reference :google_calendar_events, :google_calendar
  end
end
