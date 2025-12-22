# frozen_string_literal: true

class AddForeignKeyForFinalExamToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :google_calendar_events, :final_exams, validate: false
  end
end
