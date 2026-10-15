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

    def perform(level:, **arguments)
      scope = LEVELS[level] || raise(ToolError, "level must be one of #{LEVELS.keys.join(', ')}")
      preference = calendar_preference_for_scope(scope)

      authorize_change(preference)
      result = apply_settings!(preference, arguments)
      sync_calendar

      {
        level:    level,
        result:   result,
        settings: result == :saved ? CalendarPreferenceSerializer.new(preference).as_json : nil
      }
    end
  end
end
