# frozen_string_literal: true

module Courses
  # The final exams for the courses a user is enrolled in, in one term, in
  # date and time order. BusyBlocks::FinalExamSource uses the same join.
  class FinalExamsQuery
    def initialize(user, term)
      @user = user
      @term = term
    end

    # @return [ActiveRecord::Relation<FinalExam>]
    def call
      FinalExam
        .where(term: @term, course_id: @user.enrollments.where(term_id: @term.id).select(:course_id))
        .includes(:course)
        .order(:exam_date, :start_time)
    end
  end
end
