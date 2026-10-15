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

    def perform(meeting_time_id:, **arguments)
      meeting_time = find_my_meeting_time(meeting_time_id)
      preference   = Preferences::Resolver.new(user).get_event_preference(meeting_time) ||
                     EventPreference.new(user: user, preferenceable: meeting_time)

      authorize_change(preference)
      result = apply_settings!(preference, arguments)
      sync_calendar

      resolved = Preferences::Resolver.new(user).resolve_with_sources(meeting_time)
      context  = Preferences::TemplateRenderer.build_context_from_meeting_time(meeting_time)

      {
        meeting_time_id: meeting_time.public_id,
        course:          meeting_time.course.title,
        result:          result,
        class_settings:  result == :saved ? EventPreferenceSerializer.new(preference).as_json : nil,
        resolved:        resolved[:preferences],
        sources:         resolved[:sources],
        preview:         generate_preview(resolved[:preferences], context)
      }
    end
  end
end
