# frozen_string_literal: true

# The final exam of a course the user takes. GET /api/user/finals and the
# my_finals MCP tool send it. Load the exams with Courses::FinalExamsQuery,
# which includes the course.
class EnrolledFinalExamSerializer
  def initialize(exam)
    @exam = exam
  end

  def as_json(*)
    course = @exam.course

    {
      course:     "#{course.prefix}#{course.course_number} #{course.title}".squish,
      crn:        @exam.crn,
      date:       @exam.exam_date.iso8601,
      start_time: @exam.formatted_start_time,
      end_time:   @exam.formatted_end_time,
      location:   @exam.location
    }
  end
end
