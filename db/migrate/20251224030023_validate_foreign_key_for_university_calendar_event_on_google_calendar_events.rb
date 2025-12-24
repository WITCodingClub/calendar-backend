# frozen_string_literal: true

class ValidateForeignKeyForUniversityCalendarEventOnGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :google_calendar_events, :university_calendar_events
  end
end
