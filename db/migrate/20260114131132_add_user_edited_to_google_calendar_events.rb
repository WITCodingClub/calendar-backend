# frozen_string_literal: true

class AddUserEditedToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :google_calendar_events, :user_edited, :boolean, default: false, null: false
  end

end
