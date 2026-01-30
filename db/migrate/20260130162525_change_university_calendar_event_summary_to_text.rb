# frozen_string_literal: true

class ChangeUniversityCalendarEventSummaryToText < ActiveRecord::Migration[8.1]
  def up
    change_column :university_calendar_events, :summary, :text, null: false
  end

  def down
    # Truncate any summaries longer than 255 characters before reverting
    # This is safe because we're going back to the old behavior
    change_column :university_calendar_events, :summary, :string, limit: 255, null: false
  end

end
