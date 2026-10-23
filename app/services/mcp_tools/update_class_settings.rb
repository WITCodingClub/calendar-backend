# frozen_string_literal: true

module McpTools
  # PATCH and DELETE /api/meeting_times/:id/preference: the calendar event
  # settings of one class meeting, above the calendar-wide settings.
  class UpdateClassSettings < BaseWriteTool
    tool_name "update_class_settings"
    title "Change one class's calendar events"
    description "Changes how one weekly class meeting appears in my calendar: the event title, " \
                "description, location, color, visibility, and reminders. Only the fields you pass change. " \
                "Use reset to remove a field, so the calendar-wide setting applies again. Get the " \
                "meeting_time_id from my_courses. To change every lecture or every class, use " \
                "update_calendar_settings instead."
    requires_scope "settings:write"
    input_schema(
      properties: {
        meeting_time_id: { type: "string", description: "The meeting time id from my_courses." },
        **SETTING_PROPERTIES
      },
      required: [ "meeting_time_id" ]
    )
    # class_settings is null when the class has no settings of its own left.
    # not_changed is there only when the student did not confirm.
    output_schema(
      Schemas.object(
        {
          meeting_time_id: Schemas::STRING,
          course:          Schemas::STRING,
          result:          Schemas::SAVE_RESULT,
          class_settings:  Schemas.nullable(Schemas::SETTINGS),
          resolved:        Schemas::RESOLVED_SETTINGS,
          sources:         Schemas::SETTING_SOURCES,
          preview:         Schemas::PREVIEW,
          not_changed:     Schemas::NOT_CHANGED
        },
        optional: %i[not_changed]
      )
    )

    def perform(meeting_time_id:, **arguments)
      meeting_time = find_my_meeting_time(meeting_time_id)
      preference   = Preferences::Resolver.new(user).get_event_preference(meeting_time) ||
                     EventPreference.new(user: user, preferenceable: meeting_time)

      authorize_change(preference)
      attributes = setting_attributes(arguments)
      validate_settings!(preference, attributes)
      message    = settings_message(describe_class(meeting_time), preference, attributes)
      unchanged  = -> { settings_result(meeting_time, preference.persisted? ? preference : nil, :unchanged) }

      with_confirmation(message, unchanged: unchanged, version: record_version(preference)) do
        result = apply_settings!(preference, attributes)
        sync_calendar
        settings_result(meeting_time, result == :saved ? preference : nil, result)
      end
    end

    private

    def settings_result(meeting_time, preference, result)
      resolved = Preferences::Resolver.new(user).resolve_with_sources(meeting_time)
      context  = Preferences::TemplateRenderer.build_context_from_meeting_time(meeting_time)

      {
        meeting_time_id: meeting_time.public_id,
        course:          meeting_time.course.title,
        result:          result,
        class_settings:  preference && EventPreferenceSerializer.new(preference).as_json,
        resolved:        resolved[:preferences],
        sources:         resolved[:sources],
        preview:         generate_preview(resolved[:preferences], context)
      }
    end

    # "one class only (Data Structures, lecture, Monday, 10:00 AM - 11:40 AM)"
    def describe_class(meeting_time)
      parts = [ meeting_time.course.title, meeting_time.meeting_schedule_type, meeting_time.day_of_week&.capitalize ]
      parts << meeting_time.formatted_time_range if meeting_time.begin_time && meeting_time.end_time
      "one class only (#{parts.compact.join(', ')})"
    end
  end
end
