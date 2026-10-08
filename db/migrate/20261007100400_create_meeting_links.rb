# frozen_string_literal: true

# A one-time meeting link (#652). A person shares the link with someone who
# is not a friend. That person picks one free time, and the link is used up.
#
# Only a digest of the token is stored, like a password reset token, so a
# database read does not give anyone a working link.
#
# The guest gets the calendar invitation, so the meeting keeps the guest's
# name and email.
class CreateMeetingLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :title
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :duration_minutes, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.references :friend_meeting, foreign_key: { on_delete: :nullify }
      t.references :guest_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :meeting_links, :token_digest, unique: true

    add_column :friend_meetings, :guest_name, :string
    add_column :friend_meetings, :guest_email, :string
  end
end
