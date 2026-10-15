# frozen_string_literal: true

# Issue #686: few users need a sync at one time, so a full boolean index has
# low selectivity. Every query reads `calendar_needs_sync = true`
# (NightlySyncJob, User.needs_sync), so a partial index holds only those rows.
#
# The indexes are built and dropped concurrently, so sign-ins and syncs can
# write to users during the change.
class PartialIndexUsersOnCalendarNeedsSync < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :users, :calendar_needs_sync, name: "index_users_needing_calendar_sync",
              where: "calendar_needs_sync", algorithm: :concurrently, if_not_exists: true
    remove_index :users, name: "index_users_on_calendar_needs_sync", algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :users, :calendar_needs_sync, name: "index_users_on_calendar_needs_sync",
              algorithm: :concurrently, if_not_exists: true
    remove_index :users, name: "index_users_needing_calendar_sync", algorithm: :concurrently, if_exists: true
  end
end
