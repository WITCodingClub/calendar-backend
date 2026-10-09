# frozen_string_literal: true

module CourseCalendars
  class IcsFeed
    # One event for each upcoming final of the user's courses.
    class FinalExamEvents
      include ApplicationHelper

      def initialize(final_exams)
        @final_exams = final_exams
      end

      def append_to(cal)
        @final_exams.each do |final_exam|
          next unless final_exam.start_datetime && final_exam.end_datetime

          cal.event do |e|
            e.dtstart     = Icalendar::Values::DateTime.new(final_exam.start_datetime, tzid: TZID)
            e.dtend       = Icalendar::Values::DateTime.new(final_exam.end_datetime,   tzid: TZID)
            e.summary     = "Final Exam: #{titleize_with_roman_numerals(final_exam.course_title)}"
            e.description = final_exam.course_code
            e.location    = final_exam.location_with_names if final_exam.location.present?
            e.uid         = "final-exam-#{final_exam.id}@calendar-util.wit.edu"
            e.dtstamp     = Icalendar::Values::DateTime.new(final_exam.updated_at, tzid: TZID)
            e.last_modified = Icalendar::Values::DateTime.new(final_exam.updated_at, tzid: TZID)
            e.sequence    = (final_exam.updated_at.to_i / 60)
          end
        end
      end
    end
  end
end
