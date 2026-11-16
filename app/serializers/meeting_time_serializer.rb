# frozen_string_literal: true

# One weekly meeting of a person's course, with the title, description,
# location, color, and reminders the person's calendar gives it. The extension's course
# list, a friend's schedule, the MCP course tools, and the dashboard read it.
class MeetingTimeSerializer
  DAYS = Course::MeetingTime.day_of_weeks.keys.freeze

  # recurrence is a CourseCalendars::RecurrenceBuilder for the schedule owner.
  # It gives the same end date and no-class dates that calendar sync uses.
  def initialize(meeting_time, preference_resolver:, preview:, recurrence:)
    @mt = meeting_time
    @preference_resolver = preference_resolver
    @preview = preview
    @recurrence = recurrence
  end

  def as_json(*)
    {
      id:                  @mt.public_id,
      day_of_week:         @mt.day_of_week,
      begin_time:          @mt.begin_time ? @mt.fmt_begin_time_military : nil,
      end_time:            @mt.end_time ? @mt.fmt_end_time_military : nil,
      begin_time_display:  @mt.begin_time ? @mt.fmt_begin_time : nil,
      end_time_display:    @mt.end_time ? @mt.fmt_end_time : nil,
      building_room:       @mt.building_room,
      start_date:          @mt.start_date,
      end_date:            @mt.end_date,
      effective_end_date:  @recurrence.effective_end_date(@mt).iso8601,
      excluded_dates:      @recurrence.excluded_dates(@mt).map(&:iso8601),
      location: {
        building: building_json,
        rooms:    @mt.rooms.map(&:formatted_number)
      },
      **DAYS.to_h { |day| [ day.to_sym, @mt.day_of_week == day ] },
      calendar_config: calendar_config
    }
  end

  private

  def calendar_config
    preferences = @preference_resolver.resolve_with_sources(@mt)[:preferences]
    text        = @preview.call(preferences, Preferences::Context.for(@mt).variables)

    {
      **text,
      color_id:          Preferences::Colors.normalize(preferences[:color_id]),
      reminder_settings: preferences[:reminder_settings],
      visibility:        preferences[:visibility]
    }
  end

  def building_json
    return nil unless @mt.building

    {
      pub_id:       @mt.building.public_id,
      name:         @mt.building.name,
      abbreviation: @mt.building.abbreviation
    }
  end
end
