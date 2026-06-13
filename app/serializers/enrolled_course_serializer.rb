# frozen_string_literal: true

class EnrolledCourseSerializer
  include ApplicationHelper

  def initialize(enrollment, term:, preference_resolver:, template_renderer:)
    @enrollment = enrollment
    @term = term
    @preference_resolver = preference_resolver
    @template_renderer = template_renderer
  end

  def as_json(*)
    course = @enrollment.course
    faculty = course.faculties.first
    filtered_meeting_times = deduplicate_meeting_times(course.meeting_times)

    {
      title:          titleize_with_roman_numerals(course.title),
      subject:        course.prefix,
      course_number:  course.course_number,
      section_number: course.section_number,
      credit_hours:   course.credit_hours,
      schedule_type:  course.schedule_type,
      prefix:         course.prefix,
      instructors:    course.faculties.map { |f| [ f.first_name, f.last_name ].compact.join(" ").presence }.compact,
      term:           TermSerializer.new(@term).as_json,
      professor:      FacultySerializer.new(faculty).as_json,
      meeting_times:  filtered_meeting_times.map do |mt|
                        MeetingTimeSerializer.new(
                          mt,
                          preference_resolver: @preference_resolver,
                          template_renderer:   @template_renderer
                        ).as_json
                      end
    }
  end

  private

  def deduplicate_meeting_times(meeting_times)
    meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                 .map do |_key, group|
                   if group.size > 1
                     Rails.logger.info "[EnrolledCourseSerializer] Duplicate meeting times: #{group.size} for course #{group.first.course_id}"
                   end

                   non_tbd = group.reject { |mt| LocationHelper.tbd_building?(mt.building) || LocationHelper.tbd_room?(mt.room) }
                   non_tbd.any? ? non_tbd.first : group.first
                 end
  end
end
