class ConvertMeetingTimesFromMinutesToHhmm < ActiveRecord::Migration[8.1]
  def up
    # Convert existing minutes to HHMM format
    MeetingTime.find_each do |mt|
      # Convert minutes to HHMM: 600 minutes = 10:00 = 1000
      begin_hours = mt.begin_time / 60
      begin_mins = mt.begin_time % 60
      begin_hhmm = (begin_hours * 100) + begin_mins

      end_hours = mt.end_time / 60
      end_mins = mt.end_time % 60
      end_hhmm = (end_hours * 100) + end_mins

      mt.update_columns(
        begin_time: begin_hhmm,
        end_time: end_hhmm
      )
    end
  end

  def down
    # Convert HHMM back to minutes
    MeetingTime.find_each do |mt|
      # Convert HHMM to minutes: 1000 = 10:00 = 600 minutes
      begin_hours = mt.begin_time / 100
      begin_mins = mt.begin_time % 100
      begin_minutes = (begin_hours * 60) + begin_mins

      end_hours = mt.end_time / 100
      end_mins = mt.end_time % 100
      end_minutes = (end_hours * 60) + end_mins

      mt.update_columns(
        begin_time: begin_minutes,
        end_time: end_minutes
      )
    end
  end
end
