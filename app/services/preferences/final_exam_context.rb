# frozen_string_literal: true

module Preferences
  # A final exam. An exam whose course is not in the catalog has no course.
  class FinalExamContext < Context
    DEFAULTS = {
      title_template: "Final Exam: {{title}}",
      description_template: "{{course_code}}\n{{faculty}}",
      location_template: "{{location}}",
      reminder_settings: [
        { "time" => "1", "type" => "days", "method" => "popup" },
        { "time" => "1", "type" => "hours", "method" => "popup" },
        { "time" => "15", "type" => "minutes", "method" => "popup" }
      ],
      color_id: Preferences::Colors::TOMATO,
      visibility: "default"
    }.freeze

    def variables
      course = record.course
      date   = record.exam_date

      {
        title: course&.title || "CRN #{record.crn}",
        course_code: record.course_code,
        subject: course&.subject || "",
        course_number: course&.course_number || "",
        section_number: course&.section_number || "",
        crn: record.crn,
        room: "",
        building: "",
        location: record.location_with_names || "",
        faculty: record.primary_instructor,
        faculty_email: course&.faculties&.first&.email || "",
        all_faculty: record.all_instructors,
        start_time: record.formatted_start_time_ampm,
        end_time: record.formatted_end_time_ampm,
        day: date.strftime("%A"),
        day_abbr: date.strftime("%a"),
        term: (course ? course.term : record.term)&.name || "",
        schedule_type: "Final Exam",
        schedule_type_short: "Final",
        event_type: "final_exam",
        is_final_exam: true,
        exam_date: date.strftime("%B %d, %Y"),
        exam_date_short: date.strftime("%m/%d/%Y"),
        exam_time_of_day: record.time_of_day&.capitalize || "",
        duration: "#{record.duration_hours} hours",
        combined_crns: record.combined_crns_display
      }
    end

    def event_type = "final_exam"
  end
end
