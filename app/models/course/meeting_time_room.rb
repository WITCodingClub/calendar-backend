# frozen_string_literal: true

class Course::MeetingTimeRoom < ApplicationRecord
  self.table_name = "course_meeting_time_rooms"

  belongs_to :meeting_time, class_name: "Course::MeetingTime"
  belongs_to :room
end
