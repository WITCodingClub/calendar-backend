# frozen_string_literal: true

class CourseSuggestionSerializer
  def initialize(course)
    @course = course
  end

  def as_json(*)
    {
      id: @course.id,
      subject: @course.subject,
      course_number: @course.course_number,
      crn: @course.crn,
      title: @course.title,
      credit_hours: @course.credit_hours,
      schedule_type: @course.schedule_type,
      seats_available: @course.seats_available,
      seats_capacity: @course.seats_capacity
    }
  end

end
