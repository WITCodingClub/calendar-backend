# frozen_string_literal: true

class AddUniversityCalendarEventToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :google_calendar_events, :university_calendar_event, null: true, index: { algorithm: :concurrently }
  end
end
