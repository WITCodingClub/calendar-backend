class RenameColumnsToSnakeCaseInMeetingTimes < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      rename_column :meeting_times, :meetingScheduleType, :meeting_schedule_type
      rename_column :meeting_times, :meetingType, :meeting_type
      rename_column :meeting_times, :hoursWeek, :hours_week
    end
  end
end
