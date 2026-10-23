# frozen_string_literal: true

class BusyBlocks
  # The final exams of a user, from the courses that the user is enrolled in.
  # A final exam is busy time even though the finals period has no class days.
  class FinalExamSource
    def self.call(user, from, to) = call_many([ user ], from, to).fetch(user.id, [])

    # { user id => [Interval] }, in one query for any number of users.
    def self.call_many(users, from, to)
      FinalExam
        .joins(course: :enrollments)
        .where(enrollments: { user_id: users.map(&:id) }, exam_date: from..to)
        .distinct
        .pluck(Arel.sql("enrollments.user_id"), :exam_date, :start_time, :end_time)
        .group_by(&:first)
        .transform_values do |rows|
          rows.map { |_, date, begin_time, end_time| Interval.new(date: date, begin_time: begin_time, end_time: end_time) }
        end
    end
  end
end
