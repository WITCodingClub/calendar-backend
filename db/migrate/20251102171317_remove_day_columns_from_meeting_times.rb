class RemoveDayColumnsFromMeetingTimes < ActiveRecord::Migration[8.1]
  def change
    # Remove individual day boolean columns
    # Note: day_of_week is left nullable to avoid blocking table writes
    # Wrapped in safety_assured since model has been updated to use day_of_week
    safety_assured do
      remove_column :meeting_times, :monday, :boolean
      remove_column :meeting_times, :tuesday, :boolean
      remove_column :meeting_times, :wednesday, :boolean
      remove_column :meeting_times, :thursday, :boolean
      remove_column :meeting_times, :friday, :boolean
      remove_column :meeting_times, :saturday, :boolean
      remove_column :meeting_times, :sunday, :boolean
    end
  end
end
