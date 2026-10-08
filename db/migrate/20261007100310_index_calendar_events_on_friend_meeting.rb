# frozen_string_literal: true

# calendar_events is a large table. The indexes are built concurrently, so
# course syncs can write to the table during the build. The foreign key from
# 20261007100300 is validated here, which does not block writes.
class IndexCalendarEventsOnFriendMeeting < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :calendar_events, :friend_meeting_id, algorithm: :concurrently, if_not_exists: true
    add_index :calendar_events, [ :calendar_id, :friend_meeting_id ], unique: true,
              where: "friend_meeting_id IS NOT NULL", name: "idx_calendar_events_unique_friend_meeting",
              algorithm: :concurrently, if_not_exists: true

    reversible do |direction|
      direction.up { validate_foreign_key :calendar_events, :friend_meetings }
    end
  end
end
