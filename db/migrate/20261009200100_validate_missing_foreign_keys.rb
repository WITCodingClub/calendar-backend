# frozen_string_literal: true

# Removes rows that point at a missing parent, then validates the foreign keys
# from AddMissingForeignKeys. The keys already check new rows, so no new orphan
# can appear between the cleanup and the validation.
#
# The cleanup must run in the same deploy as the validation, or the validation
# fails and the deploy stops. For this reason it is in this migration and not in
# a rake task.
#
# Each statement commits on its own, so the rows that the cleanup changes are
# not locked while the validation scans the table. Every step can run again, so
# a deploy that stops halfway can retry.
class ValidateMissingForeignKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    safety_assured do
      # Nullify, do not delete. FinalExam and UniversityCalendarEvent use
      # dependent: :nullify, so a calendar event whose source is gone keeps its
      # row with a null id. Cleanup::OrphanedCalendarEventsJob then finds it
      # with CalendarEvent.orphaned, deletes the remote event with
      # external_event_id, and destroys the row. A deleted row would leave the
      # event on the user's calendar with no record of it.
      execute <<~SQL.squish
        UPDATE calendar_events SET final_exam_id = NULL
        WHERE final_exam_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM final_exams WHERE final_exams.id = calendar_events.final_exam_id)
      SQL
      execute <<~SQL.squish
        UPDATE calendar_events SET university_calendar_event_id = NULL
        WHERE university_calendar_event_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM university_calendar_events
            WHERE university_calendar_events.id = calendar_events.university_calendar_event_id
          )
      SQL

      # A join row with no course or no faculty has no meaning. Delete it.
      execute <<~SQL.squish
        DELETE FROM courses_faculties
        WHERE NOT EXISTS (SELECT 1 FROM courses WHERE courses.id = courses_faculties.course_id)
           OR NOT EXISTS (SELECT 1 FROM faculties WHERE faculties.id = courses_faculties.faculty_id)
      SQL
    end

    validate_foreign_key :calendar_events, :final_exams
    validate_foreign_key :calendar_events, :university_calendar_events
    validate_foreign_key :courses_faculties, :courses
    validate_foreign_key :courses_faculties, :faculties
  end

  # The removed orphans cannot come back, and the foreign keys stay valid.
  def down; end
end
