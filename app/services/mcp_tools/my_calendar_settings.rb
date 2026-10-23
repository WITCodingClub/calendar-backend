# frozen_string_literal: true

module McpTools
  # GET /api/calendar_preferences, with the settings of single classes and
  # the choices the settings tools take.
  class MyCalendarSettings < BaseTool
    tool_name "my_calendar_settings"
    title "My calendar settings"
    description "Lists my calendar event settings: the calendar-wide levels (all classes, each kind of " \
                "class, final exams, university events), the classes with their own settings, and whether " \
                "reminders are paused. Also lists the color names and template variables that the settings " \
                "tools take. A level that is not listed uses the defaults."
    requires_scope "settings:read"
    input_schema(properties: {})
    output_schema(
      Schemas.object(
        levels:                       Schemas.array(
          Schemas.object(Schemas::SETTINGS_PROPERTIES.merge(level: Schemas::STRING))
        ),
        classes:                      Schemas.array(
          Schemas.object(
            Schemas::SETTINGS_PROPERTIES.merge(meeting_time_id: Schemas::STRING, course: Schemas::STRING, term_uid: Schemas::INTEGER)
          )
        ),
        notifications_disabled_until: Schemas.nullable(Schemas::DATE_TIME),
        colors:                       {
          type:                 "object",
          description:          "Each color name, with its Google Calendar color id.",
          additionalProperties: Schemas::STRING
        },
        template_variables:           Schemas::STRINGS
      )
    )
    links { [ calendar_settings_link ] }

    def perform
      authorize user, :show?

      {
        levels:                       levels,
        classes:                      classes,
        notifications_disabled_until: user.notifications_disabled? ? user.notifications_disabled_until : nil,
        colors:                       GoogleCalendar::Colors::NAMES,
        template_variables:           Preferences::TemplateRenderer::ALLOWED_VARIABLES
      }
    end

    private

    def levels
      CalendarPreferencePolicy::Scope.new(user, user.calendar_preferences).resolve.map do |preference|
        { level: level_name(preference), **CalendarPreferenceSerializer.new(preference).as_json.except(:scope, :event_type) }
      end
    end

    def level_name(preference)
      case preference.scope
      when "global"           then "all_classes"
      when "uni_cal_global"   then "university"
      when "uni_cal_category" then "university:#{preference.event_type}"
      else preference.event_type
      end
    end

    def classes
      EventPreferencePolicy::Scope.new(user, user.event_preferences.for_meeting_times).resolve
                                  .includes(preferenceable: { course: :term })
                                  .map do |preference|
        meeting_time = preference.preferenceable
        {
          meeting_time_id: meeting_time.public_id,
          course:          meeting_time.course.title,
          term_uid:        meeting_time.course.term.uid,
          **EventPreferenceSerializer.new(preference).as_json
        }
      end
    end
  end
end
