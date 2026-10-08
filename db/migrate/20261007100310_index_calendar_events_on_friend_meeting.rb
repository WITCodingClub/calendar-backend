# frozen_string_literal: true

# calendar_events is a large table. The indexes are built concurrently, so
# course syncs can write to the table during the build. The foreign key from
# 20261007100300 is validated here, which does not block writes.
#
# A concurrent build that fails leaves an INVALID index with the same name.
# `if_not_exists` would keep that index, so the migration drops an invalid
# index first. A valid index from an earlier partial run stays.
class IndexCalendarEventsOnFriendMeeting < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXES = {
    "index_calendar_events_on_friend_meeting_id" => { columns: :friend_meeting_id },
    "idx_calendar_events_unique_friend_meeting"  => {
      columns: %i[calendar_id friend_meeting_id], unique: true, where: "friend_meeting_id IS NOT NULL"
    }
  }.freeze

  def up
    INDEXES.each do |name, options|
      drop_invalid_index(name)
      add_index :calendar_events, options[:columns], **options.except(:columns), name: name,
                algorithm: :concurrently, if_not_exists: true
    end

    validate_foreign_key :calendar_events, :friend_meetings
  end

  def down
    INDEXES.each_key do |name|
      remove_index :calendar_events, name: name, algorithm: :concurrently, if_exists: true
    end
  end

  private

  def drop_invalid_index(name)
    invalid = select_value(<<~SQL.squish)
      SELECT 1 FROM pg_index
      JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{quote(name)} AND NOT pg_index.indisvalid
    SQL
    remove_index :calendar_events, name: name, algorithm: :concurrently if invalid
  end
end
