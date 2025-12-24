# frozen_string_literal: true

class AddForeignKeyForUniversityCalendarEventToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :google_calendar_events, :university_calendar_events, validate: false
  end
end
