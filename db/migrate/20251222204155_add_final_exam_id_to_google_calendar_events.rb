# frozen_string_literal: true

class AddFinalExamIdToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :google_calendar_events, :final_exam, null: true, index: { algorithm: :concurrently }
  end
end
