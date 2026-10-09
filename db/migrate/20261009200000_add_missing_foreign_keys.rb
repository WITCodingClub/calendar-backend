# frozen_string_literal: true

# Adds the foreign keys that the audit in #713 found missing. validate: false
# skips the scan of existing rows, so the lock is short. New rows are checked at
# once. ValidateMissingForeignKeys removes old orphan rows and validates.
#
# on_delete follows what the models do today:
# - FinalExam and UniversityCalendarEvent use has_many :calendar_events,
#   dependent: :nullify, so the database nullifies too. A bulk delete that skips
#   callbacks then has the same result as destroy.
# - Course and Faculty use has_many :course_faculties, dependent: :destroy. The
#   app deletes the join rows itself, so a plain foreign key is correct.
class AddMissingForeignKeys < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :calendar_events, :final_exams, on_delete: :nullify, validate: false
    add_foreign_key :calendar_events, :university_calendar_events, on_delete: :nullify, validate: false
    add_foreign_key :courses_faculties, :courses, validate: false
    add_foreign_key :courses_faculties, :faculties, validate: false
  end
end
