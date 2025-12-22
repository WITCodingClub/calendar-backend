# frozen_string_literal: true

class ValidateForeignKeyForFinalExamOnGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :google_calendar_events, :final_exams
  end
end
