# frozen_string_literal: true

class AddUserEditedFieldsToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :google_calendar_events, :user_edited_fields, :jsonb
  end

end
