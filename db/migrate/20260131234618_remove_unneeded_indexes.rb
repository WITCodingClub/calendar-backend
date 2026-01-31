# frozen_string_literal: true

class RemoveUnneededIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :calendar_preferences, name: "index_calendar_preferences_on_user_id", column: :user_id
    remove_index :courses, name: "index_courses_on_crn", column: :crn
    remove_index :enrollment_snapshots, name: "index_enrollment_snapshots_on_user_id", column: :user_id
    remove_index :enrollments, name: "index_enrollments_on_user_id", column: :user_id
    remove_index :event_preferences, name: "index_event_prefs_on_preferenceable", column: [:preferenceable_type, :preferenceable_id]
    remove_index :event_preferences, name: "index_event_preferences_on_user_id", column: :user_id
    remove_index :finals_schedules, name: "index_finals_schedules_on_term_id", column: :term_id
    remove_index :google_calendar_events, name: "index_google_calendar_events_on_google_calendar_id", column: :google_calendar_id
    remove_index :oauth_credentials, name: "index_oauth_credentials_on_user_id", column: :user_id
    remove_index :related_professors, name: "index_related_professors_on_faculty_id", column: :faculty_id
    remove_index :teacher_rating_tags, name: "index_teacher_rating_tags_on_faculty_id", column: :faculty_id
    remove_index :university_calendar_events, name: "index_university_calendar_events_on_start_time", column: :start_time
  end

end
