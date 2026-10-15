# frozen_string_literal: true

module Dashboard
  # Helpers for the dashboard/schedules/_calendar partial, which shows the
  # signed-in user's schedule and a friend's schedule.
  module SchedulesHelper
    WEEKDAYS = %w[monday tuesday wednesday thursday friday].freeze
    WEEKEND  = %w[saturday sunday].freeze

    # The days in the week grid of the week that starts on `week_start`.
    # Saturday and Sunday show only when a course meets on that day in the term.
    def schedule_week_days(schedule)
      names = WEEKDAYS + WEEKEND.select { |day| schedule.schedule_by_day.fetch(day, []).any? }

      names.map do |name|
        schedule.week_start + (Date::DAYNAMES.index(name.capitalize) - 1) % 7
      end
    end

    # The meetings on `day`, in start time order. A meeting shows only between
    # its own start and end dates, or the term dates when it has none.
    def schedule_sessions_on(schedule, day)
      term = schedule.selected_term

      sessions = schedule.schedule_by_day.fetch(day.strftime("%A").downcase, []).select do |entry|
        mt = entry[:meeting_time]
        starts = mt[:start_date].present? ? mt[:start_date].to_date : (term.start_date || Date.new(1900, 1, 1))
        ends   = mt[:end_date].present?   ? mt[:end_date].to_date   : (term.end_date   || Date.new(2100, 12, 31))
        day.between?(starts, ends)
      end

      sessions.sort_by { |entry| entry[:meeting_time][:begin_time] || "99:99" }
    end

    # The full text of a course block: course, title, time and room. The block
    # truncates its visible text, so the title attribute and screen readers
    # use this text.
    def schedule_entry_label(entry)
      course = entry[:course]
      mt     = entry[:meeting_time]
      time   = "#{mt[:begin_time_display]} – #{mt[:end_time_display]}" if mt[:begin_time_display] && mt[:end_time_display]

      [ "#{course[:subject]} #{course[:course_number]}", course[:title], time, mt[:building_room] ]
        .compact_blank
        .join(", ")
    end

    # The style of a course block: a light tint of the course color with a
    # border in the full color. The text uses the on-surface token, so its
    # contrast does not depend on the course color.
    def schedule_entry_style(entry, border_width: 3)
      color = entry[:meeting_time].dig(:calendar_config, :color_id)
      color = GoogleCalendar::Colors::BLUEBERRY unless color.to_s.match?(GoogleCalendar::Colors::HEX_FORMAT)

      "background-color: #{color}26; border-left: #{border_width}px solid #{color}"
    end
  end
end
