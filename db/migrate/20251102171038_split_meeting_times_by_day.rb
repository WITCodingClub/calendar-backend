class SplitMeetingTimesByDay < ActiveRecord::Migration[8.1]
  # Day of week mapping (matches Ruby's Date.wday)
  DAYS_MAP = {
    sunday: 0,
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6
  }

  def up
    # Get all existing meeting times
    say_with_time "Splitting meeting times by day of week" do
      MeetingTime.find_each do |meeting_time|
        # Find which days are true
        active_days = DAYS_MAP.select do |day_name, _day_num|
          meeting_time.send(day_name)
        end

        # Skip if no days are active
        next if active_days.empty?

        # Calculate hours per day (not per week)
        begin_h = meeting_time.begin_time / 100
        begin_m = meeting_time.begin_time % 100
        begin_decimal = begin_h + (begin_m / 60.0)

        end_h = meeting_time.end_time / 100
        end_m = meeting_time.end_time % 100
        end_decimal = end_h + (end_m / 60.0)

        hours_per_day = [end_decimal - begin_decimal, 0].max.round

        # Create a new record for each active day
        active_days.each_with_index do |(day_name, day_num), index|
          if index == 0
            # Update the first record instead of creating a new one
            meeting_time.update_columns(
              day_of_week: day_num,
              hours_week: hours_per_day
            )
          else
            # Create new records for additional days
            MeetingTime.create!(
              course_id: meeting_time.course_id,
              room_id: meeting_time.room_id,
              begin_time: meeting_time.begin_time,
              end_time: meeting_time.end_time,
              start_date: meeting_time.start_date,
              end_date: meeting_time.end_date,
              hours_week: hours_per_day,
              meeting_schedule_type: meeting_time.meeting_schedule_type,
              meeting_type: meeting_time.meeting_type,
              day_of_week: day_num,
              monday: meeting_time.monday,
              tuesday: meeting_time.tuesday,
              wednesday: meeting_time.wednesday,
              thursday: meeting_time.thursday,
              friday: meeting_time.friday,
              saturday: meeting_time.saturday,
              sunday: meeting_time.sunday
            )
          end
        end
      end
    end
  end

  def down
    # Reversing this migration would require combining records back together,
    # which is complex and likely not needed. If needed, implement custom logic.
    raise ActiveRecord::IrreversibleMigration
  end
end
