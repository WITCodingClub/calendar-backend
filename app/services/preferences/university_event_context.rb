# frozen_string_literal: true

module Preferences
  # A UniversityCalendarEvent: a holiday, a finals period, or an event of a
  # category the person syncs.
  class UniversityEventContext < Context
    # All-day events start at midnight, so "1 day before" fires at 12AM the
    # day before. 15 hours before start is 9AM the day before, which people read.
    ALL_DAY_REMINDERS = [ { "time" => "15", "type" => "hours", "method" => "popup" } ].freeze
    TIMED_REMINDERS   = [ { "time" => "30", "type" => "minutes", "method" => "popup" } ].freeze

    DEFAULTS = {
      title_template: "{{summary}}",
      description_template: "{{description}}",
      location_template: "{{location}}",
      reminder_settings: ALL_DAY_REMINDERS,
      color_id: Preferences::Colors::GRAPHITE,
      visibility: "default"
    }.freeze

    def variables
      term = record.term&.name || record.academic_term || ""

      {
        summary: record.summary || "",
        title: record.summary || "",
        description: record.description || "",
        location: record.location || "",
        category: record.category || "",
        organization: record.organization || "",
        academic_term: term,
        term: term,
        event_type: "university_calendar",
        start_time: clock_time(record.start_time),
        end_time: clock_time(record.end_time),
        day: record.start_time&.strftime("%A") || "",
        day_abbr: record.start_time&.strftime("%a") || "",
        course_code: "",
        subject: "",
        course_number: "",
        section_number: "",
        crn: "",
        room: "",
        building: "",
        faculty: "",
        faculty_email: "",
        all_faculty: "",
        schedule_type: record.category&.titleize || "",
        schedule_type_short: record.category || "",
        is_final_exam: false,
        exam_date: "",
        exam_date_short: "",
        exam_time_of_day: "",
        duration: "",
        combined_crns: ""
      }
    end

    def university_category = record.category

    def university_event? = true

    def default(field, config)
      return super unless field == :reminder_settings

      record.all_day? ? ALL_DAY_REMINDERS : TIMED_REMINDERS
    end

    private

    def clock_time(time) = time ? time.strftime("%-I:%M %p") : ""
  end
end
