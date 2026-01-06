# frozen_string_literal: true

class AddUniqueIndexToGoogleCalendarEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  
  def change
    # Remove existing duplicates before adding the constraint
    reversible do |dir|
      dir.up do
        safety_assured do
          # Clean up existing duplicates - keep the newest one
          execute <<-SQL
            DELETE FROM google_calendar_events g1
            USING google_calendar_events g2
            WHERE g1.id < g2.id
              AND g1.google_calendar_id = g2.google_calendar_id
              AND (
                (g1.meeting_time_id IS NOT NULL AND g1.meeting_time_id = g2.meeting_time_id)
                OR (g1.final_exam_id IS NOT NULL AND g1.final_exam_id = g2.final_exam_id)
                OR (g1.university_calendar_event_id IS NOT NULL AND g1.university_calendar_event_id = g2.university_calendar_event_id)
              )
          SQL
        end
      end
    end
    
    # Add unique indexes to prevent future duplicates
    add_index :google_calendar_events, [:google_calendar_id, :meeting_time_id], 
              unique: true, 
              where: "meeting_time_id IS NOT NULL",
              name: "idx_gcal_events_unique_meeting_time",
              algorithm: :concurrently
              
    add_index :google_calendar_events, [:google_calendar_id, :final_exam_id], 
              unique: true, 
              where: "final_exam_id IS NOT NULL",
              name: "idx_gcal_events_unique_final_exam",
              algorithm: :concurrently
              
    add_index :google_calendar_events, [:google_calendar_id, :university_calendar_event_id], 
              unique: true, 
              where: "university_calendar_event_id IS NOT NULL",
              name: "idx_gcal_events_unique_university",
              algorithm: :concurrently
  end
end
