# frozen_string_literal: true

# The Google sync stamped only each event, so every Google calendar kept a
# null last_synced_at and the admin pages showed "Never synced". Copy the
# latest event sync time to each calendar that has none.
class BackfillGoogleCalendarLastSyncedAt < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE calendars
      SET last_synced_at = synced.latest
      FROM (
        SELECT calendar_id, MAX(last_synced_at) AS latest
        FROM calendar_events
        GROUP BY calendar_id
      ) AS synced
      WHERE synced.calendar_id = calendars.id
        AND calendars.provider = 'google'
        AND calendars.last_synced_at IS NULL
        AND synced.latest IS NOT NULL
    SQL
  end

  # The next sync writes the same column, so there is nothing to undo.
  def down; end
end
