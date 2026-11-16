# frozen_string_literal: true

module Preferences
  # A class meeting (Course::MeetingTime).
  class MeetingTimeContext < Context
    DEFAULTS = {
      title_template: "{% if schedule_type == 'Laboratory' %}{{title | remove: ' - Lab'}} - {{schedule_type_short}}{% else %}{{title}}{% endif %}",
      description_template: "{{faculty}}\n{{faculty_email}}",
      location_template: "{{building}} {{room}}",
      reminder_settings: [ { "time" => "30", "type" => "minutes", "method" => "popup" } ],
      color_id: nil,
      visibility: "default"
    }.freeze

    def variables
      course     = record.course
      building   = record.building
      real_rooms = record.rooms.reject(&:tbd?)
      faculty    = course.faculties.first

      {
        title: course.title,
        course_code: "#{course.subject}-#{course.course_number}-#{course.section_number}",
        subject: course.subject,
        course_number: course.course_number,
        section_number: course.section_number,
        crn: course.crn,
        # Placeholder rooms and buildings (Room#tbd?, Building#tbd?) do not
        # show. With no real room, room is "TBD" when the catalog has a
        # placeholder, else blank (Course::MeetingTime#location_text).
        room: real_rooms.any? ? real_rooms.map(&:formatted_number).join(Room::LIST_SEPARATOR) : record.location_text.to_s,
        building: building.nil? || building.tbd? ? "" : building.name,
        location: record.location_text || "",
        faculty: faculty&.full_name || "",
        faculty_email: faculty&.email || "",
        all_faculty: course.faculties.map(&:full_name).join(", "),
        start_time: record.begin_time ? record.fmt_begin_time : "",
        end_time: record.end_time ? record.fmt_end_time : "",
        day: record.day_of_week&.titleize || "",
        day_abbr: record.day_of_week&.first(3)&.capitalize || "",
        term: course.term&.name || "",
        schedule_type: course.schedule_type&.capitalize || "",
        schedule_type_short: schedule_type_short(course.schedule_type),
        event_type: "class",
        is_final_exam: false,
        exam_date: "",
        exam_date_short: "",
        exam_time_of_day: "",
        duration: "",
        combined_crns: course.crn.to_s
      }
    end

    def event_type = record.course&.schedule_type

    # The person's default color for lectures or labs, else the color of the
    # meeting's own schedule type.
    def default(field, config)
      return super unless field == :color_id

      config&.default_color_for(event_type).presence || record.event_color
    end

    private

    def schedule_type_short(schedule_type)
      return "" if schedule_type.nil?

      schedule_type == "laboratory" ? "Lab" : schedule_type.capitalize
    end
  end
end
