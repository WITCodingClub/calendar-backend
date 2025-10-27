class RenameAcademicClassIdToCourseIdInMeetingTimes < ActiveRecord::Migration[8.1]
  def change
    safety_assured { rename_column :meeting_times, :academic_class_id, :course_id }
  end
end
