# frozen_string_literal: true

class Course::MeetingTime < ApplicationRecord
  self.table_name = "course_meeting_times"

  belongs_to :course
  belongs_to :room

  enum :meeting_schedule_type, { lecture: 1, laboratory: 2 }
  enum :meeting_type,          { class_meeting: 1 }
  enum :day_of_week,           { sunday: 0, monday: 1, tuesday: 2, wednesday: 3,
                                 thursday: 4, friday: 5, saturday: 6 }
end
