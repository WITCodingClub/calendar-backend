# frozen_string_literal: true

class BusyBlocks
  # The final exams of a user, from the courses that the user is enrolled in.
  # A final exam is busy time even though the finals period has no class days.
  class FinalExamSource
    def self.call(user, from, to)
      FinalExam
        .joins(course: :enrollments)
        .where(enrollments: { user_id: user.id }, exam_date: from..to)
        .distinct
        .pluck(:exam_date, :start_time, :end_time)
        .map { |date, begin_time, end_time| Interval.new(date: date, begin_time: begin_time, end_time: end_time) }
    end
  end
end
