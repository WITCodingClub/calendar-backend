# frozen_string_literal: true

# The calendar tables were named for Google because Google was the only
# provider. Microsoft Graph is the second one, so the tables become
# provider-neutral and carry a `provider` column instead.
#
# Every existing row is a Google row, so `provider` defaults to "google" and
# the backfill is the default itself. No calendar data moves.
#
# The model classes are renamed too (GoogleCalendarEvent -> CalendarEvent), so
# polymorphic event preferences that name the old class are rewritten.
class GeneralizeCalendarsForMultipleProviders < ActiveRecord::Migration[8.1]
  def up
    rename_table :google_calendars, :calendars
    rename_table :google_calendar_events, :calendar_events

    rename_column :calendars, :google_calendar_id, :external_calendar_id
    rename_column :calendar_events, :google_calendar_id, :calendar_id
    rename_column :calendar_events, :google_event_id, :external_event_id

    add_column :calendars, :provider, :string, null: false, default: "google"

    # Graph event ids change when an event moves between folders. iCalUId does
    # not, so it is the stable handle for reconciliation. Google does not need
    # it, so the column stays nullable.
    add_column :calendar_events, :external_ical_uid, :string

    normalize_index_names

    # An external id is only unique inside one provider.
    remove_index :calendars, name: "index_calendars_on_external_calendar_id"
    add_index :calendars, [ :provider, :external_calendar_id ],
              unique: true, name: "index_calendars_on_provider_and_external_calendar_id"

    add_index :calendar_events, :external_ical_uid,
              name: "index_calendar_events_on_external_ical_uid"

    execute <<~SQL.squish
      UPDATE event_preferences SET preferenceable_type = 'CalendarEvent'
      WHERE preferenceable_type = 'GoogleCalendarEvent'
    SQL
  end

  def down
    # The old tables cannot hold a second provider: the external id was unique
    # across every row and nothing recorded the provider.
    if select_value("SELECT 1 FROM calendars WHERE provider <> 'google' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "calendars holds non-Google rows. Remove them before rolling back."
    end

    execute <<~SQL.squish
      UPDATE event_preferences SET preferenceable_type = 'GoogleCalendarEvent'
      WHERE preferenceable_type = 'CalendarEvent'
    SQL

    remove_index :calendar_events, name: "index_calendar_events_on_external_ical_uid"
    remove_index :calendars, name: "index_calendars_on_provider_and_external_calendar_id"

    remove_column :calendar_events, :external_ical_uid
    remove_column :calendars, :provider

    restore_index_names

    rename_column :calendar_events, :external_event_id, :google_event_id
    rename_column :calendar_events, :calendar_id, :google_calendar_id
    rename_column :calendars, :external_calendar_id, :google_calendar_id

    rename_table :calendar_events, :google_calendar_events
    rename_table :calendars, :google_calendars

    add_index :google_calendars, :google_calendar_id,
              unique: true, name: "index_google_calendars_on_google_calendar_id"
  end

  private

  # rename_table and rename_column only rename indexes that follow the default
  # naming convention. The hand-named ones need doing here.
  HAND_NAMED_INDEXES = [
    [ "calendars", "index_google_calendars_on_oauth_credential_id_unique",
      "index_calendars_on_oauth_credential_id_unique" ],
    [ "calendar_events", "idx_gcal_events_unique_final_exam",
      "idx_calendar_events_unique_final_exam" ],
    [ "calendar_events", "idx_gcal_events_unique_meeting_time",
      "idx_calendar_events_unique_meeting_time" ],
    [ "calendar_events", "idx_gcal_events_unique_university",
      "idx_calendar_events_unique_university" ],
    [ "calendar_events", "idx_on_google_calendar_id_meeting_time_id",
      "idx_calendar_events_on_calendar_id_meeting_time_id" ]
  ].freeze

  def normalize_index_names
    HAND_NAMED_INDEXES.each { |table, old_name, new_name| rename_index_if_exists(table, old_name, new_name) }
  end

  def restore_index_names
    HAND_NAMED_INDEXES.each { |table, old_name, new_name| rename_index_if_exists(table, new_name, old_name) }
  end

  def rename_index_if_exists(table, from, to)
    return unless index_name_exists?(table, from)

    rename_index table, from, to
  end
end
