# frozen_string_literal: true

# Serializes a course enrollment into structured JSON for the browser extension.
# Handles meeting time deduplication (preferring non-TBD locations) and
# preference resolution for each meeting time.
class EnrolledCourseSerializer
  include ApplicationHelper

  # @param enrollment [Enrollment]
  # @param term [Term]
  # @param preference_resolver [PreferenceResolver] shared resolver instance across a collection
  # @param template_renderer [CalendarTemplateRenderer] shared renderer instance across a collection
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
      title: titleize_with_roman_numerals(course.title),
      course_number: course.course_number,
      schedule_type: course.schedule_type,
      prefix: course.prefix,
      term: TermSerializer.new(@term).as_json,
      professor: FacultySerializer.new(faculty).as_json,
      meeting_times: filtered_meeting_times.map do |mt|
        MeetingTimeSerializer.new(mt, preference_resolver: @preference_resolver, template_renderer: @template_renderer).as_json
      end
    }
  end

  private

  # Filter meeting times to prefer valid locations over TBD duplicates.
  # When multiple meeting times share the same day/time slot, pick non-TBD over TBD.
  def deduplicate_meeting_times(meeting_times)
    meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                 .map do |_key, group|
                   if group.size > 1
                     Rails.logger.info "[EnrolledCourseSerializer] Duplicate meeting times: #{group.size} entries for course #{group.first.course_id}"
                   end

                   non_tbd = group.reject { |mt| tbd_building?(mt.building) || tbd_room?(mt.room) }
                   non_tbd.any? ? non_tbd.first : group.first
                 end
  end

  def tbd_building?(building)
    return false unless building

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  def tbd_room?(room)
    return false unless room

    room.number == 0
  end

end
