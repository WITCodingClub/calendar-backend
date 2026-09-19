class RemoveUnneededIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :calendar_preferences, name: "index_calendar_preferences_on_user_id", column: :user_id
    remove_index :courses, name: "index_courses_on_term_id", column: :term_id
    remove_index :courses_faculties, name: "index_courses_faculties_on_course_id", column: :course_id
    remove_index :enrollment_snapshots, name: "index_enrollment_snapshots_on_user_id", column: :user_id
    remove_index :enrollments, name: "index_enrollments_on_user_id", column: :user_id
    remove_index :event_preferences, name: "index_event_preferences_on_user_id", column: :user_id
    remove_index :finals_schedules, name: "index_finals_schedules_on_term_id", column: :term_id
    remove_index :friendships, name: "index_friendships_on_addressee_id", column: :addressee_id
    remove_index :friendships, name: "index_friendships_on_requester_id", column: :requester_id
    remove_calendar_events_calendar_index
    remove_index :oauth_credentials, name: "index_oauth_credentials_on_user_id", column: :user_id
    remove_index :passkeys, name: "index_passkeys_on_user_id", column: :user_id
    remove_index :related_professors, name: "index_related_professors_on_faculty_id", column: :faculty_id
    remove_index :rooms, name: "index_rooms_on_building_id", column: :building_id
    remove_index :teacher_rating_tags, name: "index_teacher_rating_tags_on_faculty_id", column: :faculty_id
    remove_index :user_sessions, name: "index_user_sessions_on_user_id", column: :user_id
  end

  private

  # GeneralizeCalendarsForMultipleProviders (20260914120000) renames
  # google_calendar_events to calendar_events. It has an older version than
  # this migration, but it merged later. A database that already ran this
  # migration removed the index under its Google name. A database that runs
  # both in one `db:migrate` runs the rename first, so the index has its new
  # name by now. Both ways end with the same schema.
  def remove_calendar_events_calendar_index
    if table_exists?(:google_calendar_events)
      remove_index :google_calendar_events, name: "index_google_calendar_events_on_google_calendar_id", column: :google_calendar_id
    else
      remove_index :calendar_events, name: "index_calendar_events_on_calendar_id", column: :calendar_id
    end
  end
end
