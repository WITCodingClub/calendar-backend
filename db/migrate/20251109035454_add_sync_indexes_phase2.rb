# frozen_string_literal: true

class AddSyncIndexesPhase2 < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Nightly sync job filtering: NightlyCalendarSyncJob queries users with calendar_needs_sync = true
    # Speeds up WHERE calendar_needs_sync = true queries
    add_index :users, :calendar_needs_sync, if_not_exists: true, algorithm: :concurrently

    # Initial sync detection: Queries users WHERE last_calendar_sync_at IS NULL
    # Speeds up sync job queries that detect users who have never synced
    add_index :users, :last_calendar_sync_at, if_not_exists: true, algorithm: :concurrently

    # Calendar staleness detection: Identifies calendars that haven't synced recently
    # Used in sync scheduling and health checks
    add_index :google_calendars, :last_synced_at, if_not_exists: true, algorithm: :concurrently

    # Event staleness detection: GoogleCalendarEvent.stale scope queries by last_synced_at
    # WHERE last_synced_at IS NULL OR last_synced_at < time_ago
    add_index :google_calendar_events, :last_synced_at, if_not_exists: true, algorithm: :concurrently
  end
end
