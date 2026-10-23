# frozen_string_literal: true

# The final exam of a course the user takes. GET /api/user/finals and the
# my_finals MCP tool send it. Load the exams with Courses::FinalExamsQuery,
# which includes the course.
class EnrolledFinalExamSerializer
  # Finds the rooms of every exam with one set of queries.
  def self.render_collection(exams)
    rooms_by_exam = FinalExam.part_rooms_for(exams)
    exams.map { |exam| new(exam, part_rooms: rooms_by_exam[exam]).as_json }
  end

  # part_rooms: the exam's entry from FinalExam.part_rooms_for.
  def initialize(exam, part_rooms: nil)
    @exam = exam
    @part_rooms = part_rooms
  end

  def as_json(*)
    course = @exam.course

    {
      id:            @exam.public_id,
      course:        "#{course.prefix}#{course.course_number} #{course.title}".squish,
      crn:           @exam.crn,
      date:          @exam.exam_date.iso8601,
      start_time:    @exam.formatted_start_time,
      end_time:      @exam.formatted_end_time,
      location:      @exam.location,
      location_name: @part_rooms ? @exam.location_with_names(@part_rooms) : @exam.location_with_names
    }
  end
end
