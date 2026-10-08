# frozen_string_literal: true

# A person makes a meeting from a time when they and some friends are free.
# The meeting is its own record, so a course sync never deletes it and the ICS
# feed can show it. Each provider event for the meeting is a calendar_events
# row with friend_meeting_id, so the existing remote delete and cleanup code
# tracks it like a course event.
#
# calendar_events is a large table, so its two indexes are built concurrently
# in 20261007100310, and that migration also validates the foreign key.
class CreateFriendMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :friend_meetings do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :term, foreign_key: true
      t.string :title, null: false
      t.string :location
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :frequency, null: false, default: "one_time"
      t.date :repeat_until
      t.boolean :invite_friends, null: false, default: false
      # Set when the owner deletes the meeting. The row stays until its
      # provider events are gone, so no sync puts the meeting back.
      t.datetime :cancelled_at
      # The client's Idempotency-Key. A retry with the same key gets the
      # same meeting back.
      t.string :idempotency_key
      t.timestamps
    end
    add_index :friend_meetings, [ :user_id, :idempotency_key ], unique: true,
              where: "idempotency_key IS NOT NULL", name: "idx_friend_meetings_unique_idempotency_key"
    add_index :friend_meetings, :user_id

    create_table :friend_meeting_attendees do |t|
      t.references :friend_meeting, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :friend_meeting_attendees, [ :friend_meeting_id, :user_id ], unique: true,
              name: "idx_friend_meeting_attendees_unique"

    # One row for each place that the person picked for the meeting: a
    # provider calendar or the ICS feed.
    create_table :friend_meeting_publications do |t|
      t.references :friend_meeting, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      t.string :status, null: false, default: "queued"
      t.boolean :sends_invitations, null: false, default: false
      t.datetime :invitations_sent_at
      t.string :last_error
      t.timestamps
    end
    add_index :friend_meeting_publications, [ :friend_meeting_id, :provider ], unique: true,
              name: "idx_friend_meeting_publications_unique"

    # No index here and an unvalidated foreign key, so the lock on
    # calendar_events is short. 20261007100310 adds the rest.
    add_reference :calendar_events, :friend_meeting, index: false, foreign_key: { validate: false }
  end
end
