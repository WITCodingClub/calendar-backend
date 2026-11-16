# frozen_string_literal: true

class EnrolledCourseSerializer
  def initialize(enrollment, term:, preference_resolver:, template_renderer:, recurrence:)
    @enrollment = enrollment
    @term = term
    @preference_resolver = preference_resolver
    @template_renderer = template_renderer
    @recurrence = recurrence
  end

  def as_json(*)
    course = @enrollment.course
    faculty = course.faculties.first

    {
      title:          course.title,
      crn:            course.crn,
      subject:        course.prefix,
      course_number:  course.course_number,
      section_number: course.section_number,
      credit_hours:   course.credit_hours,
      schedule_type:  course.schedule_type,
      prefix:         course.prefix,
      instructors:    course.faculties.map { |f| [ f.first_name, f.last_name ].compact.join(" ").presence }.compact,
      term:           TermSerializer.new(@term).as_json,
      professor:      FacultySerializer.new(faculty).as_json,
      meeting_times:  course.filtered_meeting_times.map do |mt|
                        MeetingTimeSerializer.new(
                          mt,
                          preference_resolver: @preference_resolver,
                          template_renderer:   @template_renderer,
                          recurrence:          @recurrence
                        ).as_json
                      end
    }
  end
end
