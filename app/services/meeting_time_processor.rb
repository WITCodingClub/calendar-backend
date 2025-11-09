# frozen_string_literal: true

class MeetingTimeProcessor
  # Process a single meeting time into a format suitable for API responses
  def self.process_meeting_time(meeting_time)
    {
      id: meeting_time.id,
      begin_time: meeting_time.fmt_begin_time,
      end_time: meeting_time.fmt_end_time,
      start_date: meeting_time.start_date,
      end_date: meeting_time.end_date,
      day_of_week: meeting_time.day_of_week,
      meeting_schedule_type: meeting_time.meeting_schedule_type,
      location: {
        building: if meeting_time.building
                    {
                      name: meeting_time.building.name,
                      abbreviation: meeting_time.building.abbreviation
                    }
                  else
                    nil
                  end,
        room: meeting_time.room&.formatted_number
      },
      course: {
        id: meeting_time.course.id,
        title: meeting_time.course.title,
        course_number: meeting_time.course.course_number,
        prefix: meeting_time.course.prefix,
        crn: meeting_time.course.crn
      }
    }
  end

end
