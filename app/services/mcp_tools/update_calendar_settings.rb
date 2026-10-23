# frozen_string_literal: true

module McpTools
  # PATCH and DELETE /api/calendar_preferences/:scope: the calendar settings
  # of one level. A class's own settings (update_class_settings) come first,
  # then the schedule type or final exams, then every class.
  class UpdateCalendarSettings < BaseWriteTool
    # The level names of this tool, and the scope parameter of the API for
    # each (PreferenceParams#calendar_preference_for_scope).
    LEVELS = {
      "all_classes" => "global",
      "final_exam"  => "final_exam",
      "university"  => PreferenceParams::UNI_CAL_GLOBAL_SCOPE_PARAM
    }.merge(Course::ScheduleType::TYPES.keys.to_h { |key| [ key.to_s, key.to_s ] })
     .merge(CalendarPreference::UNI_CAL_CATEGORIES.to_h do |category|
       [ "university:#{category}", "#{PreferenceParams::UNI_CAL_CATEGORY_SCOPE_PREFIX}#{category}" ]
     end)
     .freeze

    tool_name "update_calendar_settings"
    title "Change calendar settings"
    description "Changes the calendar event settings for a group of events: all_classes, one kind of " \
                "class (lecture, laboratory, and the other schedule types), final_exam, university (every " \
                "university calendar event), or one university category (university:holiday). Only the " \
                "fields you pass change. Use reset to remove a field, so the level below applies again. " \
                "A class's own settings from update_class_settings still come first."
    requires_scope "settings:write"
    input_schema(
      properties: {
        level: { type: "string", enum: LEVELS.keys, description: "Which events the settings apply to." },
        **SETTING_PROPERTIES
      },
      required: [ "level" ]
    )
    # settings is null when the level has no settings left. not_changed is
    # there only when the student did not confirm.
    output_schema(
      Schemas.object(
        {
          level:       { type: "string", enum: LEVELS.keys },
          result:      Schemas::SAVE_RESULT,
          settings:    Schemas.nullable(Schemas::CALENDAR_SETTINGS),
          not_changed: Schemas::NOT_CHANGED
        },
        optional: %i[not_changed]
      )
    )

    def perform(level:, **arguments)
      scope = LEVELS[level] || raise(ToolError, "level must be one of #{LEVELS.keys.join(', ')}")
      preference = calendar_preference_for_scope(scope)

      authorize_change(preference)
      attributes = setting_attributes(arguments)
      message    = settings_message(describe_level(level), preference, attributes)
      message  &&= "#{message}\nA class with settings of its own keeps them."
      unchanged  = -> { settings_result(level, preference.persisted? ? preference : nil, :unchanged) }

      with_confirmation(message, unchanged: unchanged) do
        result = apply_settings!(preference, attributes)
        sync_calendar
        settings_result(level, result == :saved ? preference : nil, result)
      end
    end

    private

    def settings_result(level, preference, result)
      { level: level, result: result, settings: preference && CalendarPreferenceSerializer.new(preference).as_json }
    end

    def describe_level(level)
      case level
      when "all_classes" then "all your classes"
      when "final_exam" then "your final exams"
      when "university" then "all university calendar events"
      when /\Auniversity:(.+)\z/ then "the university calendar events in the #{Regexp.last_match(1).humanize(capitalize: false)} category"
      else "every #{Course::ScheduleType.new(level).readable_description} class"
      end
    end
  end
end
