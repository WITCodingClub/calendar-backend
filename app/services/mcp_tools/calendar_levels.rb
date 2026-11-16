# frozen_string_literal: true

module McpTools
  # The level names of the calendar settings tools, and the preference level
  # (Preferences::ScopeParam) that each one names.
  module CalendarLevels
    SCOPES = {
      "all_classes" => Preferences::ScopeParam::GLOBAL,
      "final_exam"  => "final_exam",
      "university"  => Preferences::ScopeParam::UNI_CAL
    }.merge(Course::ScheduleType::TYPES.keys.to_h { |key| [ key.to_s, key.to_s ] })
     .merge(CalendarPreference::UNI_CAL_CATEGORIES.to_h do |category|
       [ "university:#{category}", "#{Preferences::ScopeParam::UNI_CAL_CATEGORY_PREFIX}#{category}" ]
     end)
     .freeze

    NAMES = SCOPES.keys.freeze

    module_function

    def scope_for(level) = SCOPES[level]

    # The level name of a preference row.
    def name_for(preference)
      scope = Preferences::ScopeParam.for(preference)
      SCOPES.key(scope) || scope
    end
  end
end
