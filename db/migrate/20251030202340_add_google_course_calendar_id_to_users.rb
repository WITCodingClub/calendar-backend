class AddGoogleCourseCalendarIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :google_course_calendar_id, :string
  end
end
