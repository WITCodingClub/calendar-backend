# frozen_string_literal: true

module Preferences
  # The flat string that names one calendar preference level, so the API, the
  # dashboard and the MCP tools address every level with one URL segment:
  #   "global"            -> class defaults
  #   "uni_cal"           -> every university calendar event
  #   "uni_cal:holiday"   -> one university calendar category
  #   "lecture"           -> one course schedule type (or "final_exam")
  #
  # A uni_cal:<category> row still takes color_id, because extension builds
  # before #498 write the university color that way and ignore the response.
  # The color is not permanent: the next save of a uni_cal color clears every
  # category color (see CalendarPreference#clear_category_colors).
  module ScopeParam
    GLOBAL                  = "global"
    UNI_CAL                 = "uni_cal"
    UNI_CAL_CATEGORY_PREFIX = "uni_cal:"

    module_function

    # The user's row for the level, or a new one.
    def find_or_initialize(user, param)
      param = param.to_s
      rows  = user.calendar_preferences

      if param == GLOBAL
        rows.find_or_initialize_by(scope: :global)
      elsif param == UNI_CAL
        rows.find_or_initialize_by(scope: :uni_cal_global)
      elsif param.start_with?(UNI_CAL_CATEGORY_PREFIX)
        rows.find_or_initialize_by(scope: :uni_cal_category, event_type: param.delete_prefix(UNI_CAL_CATEGORY_PREFIX))
      else
        rows.find_or_initialize_by(scope: :event_type, event_type: param)
      end
    end

    # The string that names the level of +preference+.
    def for(preference)
      case preference.scope
      when "global"           then GLOBAL
      when "uni_cal_global"   then UNI_CAL
      when "uni_cal_category" then "#{UNI_CAL_CATEGORY_PREFIX}#{preference.event_type}"
      else preference.event_type
      end
    end
  end
end
