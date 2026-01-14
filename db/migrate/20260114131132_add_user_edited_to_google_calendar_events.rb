# frozen_string_literal: true

class AddUserEditedToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    # Store which specific fields the user has edited in Google Calendar
    # This allows field-level merging: preserve user edits while still applying system changes to other fields
    # Stored as JSON array: ["summary", "location", "description"]
    add_column :google_calendar_events, :user_edited_fields, :text
  end
end
