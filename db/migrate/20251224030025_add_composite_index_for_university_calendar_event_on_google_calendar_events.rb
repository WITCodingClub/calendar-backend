# frozen_string_literal: true

class AddCompositeIndexForUniversityCalendarEventOnGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :google_calendar_events,
              %i[google_calendar_id university_calendar_event_id],
              name: "idx_gcal_events_on_calendar_and_uni_event",
              algorithm: :concurrently
  end
end
