# frozen_string_literal: true

# A person makes a meeting from a time when they and some friends are free.
# The meeting is its own record, so a course sync never deletes it and the ICS
# feed can show it. Each provider event for the meeting is a calendar_events
# row with friend_meeting_id, so the existing remote delete and cleanup code
# tracks it like a course event.
class CreateFriendMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :friend_meetings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, foreign_key: true
      t.string :title, null: false
      t.string :location
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :frequency, null: false, default: "one_time"
      t.date :repeat_until
      t.boolean :invite_friends, null: false, default: false
      t.timestamps
    end

    create_table :friend_meeting_attendees do |t|
      t.references :friend_meeting, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :friend_meeting_attendees, [ :friend_meeting_id, :user_id ], unique: true,
              name: "idx_friend_meeting_attendees_unique"

    add_reference :calendar_events, :friend_meeting, foreign_key: true, index: true
    add_index :calendar_events, [ :calendar_id, :friend_meeting_id ], unique: true,
              where: "friend_meeting_id IS NOT NULL", name: "idx_calendar_events_unique_friend_meeting"
  end
end
