# frozen_string_literal: true

# Shared strong-parameter helpers for calendar/event preference controllers.
# Included by both Api:: and Dashboard:: preference controllers so JSON and
# form paths stay in lockstep (color hex↔id, reminder normalization).
module PreferenceParams
  extend ActiveSupport::Concern

  UNI_CAL_GLOBAL_SCOPE_PARAM = "uni_cal"
  UNI_CAL_CATEGORY_SCOPE_PREFIX = "uni_cal:"
  # Sent instead of a reminder list to drop an override and fall back to the
  # level below it. An empty list means "no reminders", which is not the same.
  RESET_REMINDER_SETTINGS = "default"

  private

  # Scope params are flat strings so the extension and the dashboard can address
  # every preference level with one URL segment:
  #   "global"            -> class defaults
  #   "uni_cal"           -> every university calendar event
  #   "uni_cal:holiday"   -> one university calendar category
  #   "lecture"           -> one course schedule type
  def calendar_preference_for_scope(scope_param)
    scope_param = scope_param.to_s

    if scope_param == "global"
      current_user.calendar_preferences.find_or_initialize_by(scope: :global)
    elsif scope_param == UNI_CAL_GLOBAL_SCOPE_PARAM
      current_user.calendar_preferences.find_or_initialize_by(scope: :uni_cal_global)
    elsif scope_param.start_with?(UNI_CAL_CATEGORY_SCOPE_PREFIX)
      current_user.calendar_preferences.find_or_initialize_by(
        scope: :uni_cal_category, event_type: scope_param.delete_prefix(UNI_CAL_CATEGORY_SCOPE_PREFIX)
      )
    else
      current_user.calendar_preferences.find_or_initialize_by(scope: :event_type, event_type: scope_param)
    end
  end

  def calendar_preference_params
    permitted = params.require(:calendar_preference).permit(
      :title_template, :description_template, :location_template,
      :color_id, :visibility, reminder_settings: []
    )

    apply_reminder_settings(permitted, params[:calendar_preference])

    if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
      permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
    end

    permitted
  end

  def event_preference_params
    permitted = params.require(:event_preference).permit(
      :title_template, :description_template, :location_template,
      :color_id, :visibility, reminder_settings: []
    )

    apply_reminder_settings(permitted, params[:event_preference])

    if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
      permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
    end

    permitted
  end

  # Writes the reminder list onto the permitted params:
  #   absent             -> the stored value stays as it is
  #   "default"          -> nil, so the next level down applies
  #   [] or blank        -> no reminders at all
  #   a list of reminders -> that list
  def apply_reminder_settings(permitted, source)
    return unless source.key?(:reminder_settings)

    raw = source[:reminder_settings]

    if raw == RESET_REMINDER_SETTINGS
      permitted[:reminder_settings] = nil
      return
    end

    # A form sends an empty list as [""], so keep only the reminder hashes.
    reminders = raw.is_a?(Array) ? raw : []
    permitted[:reminder_settings] = reminders.filter_map do |reminder|
      reminder.permit(:time, :method, :type) if reminder.respond_to?(:permit)
    end
  end

  def generate_preview(resolved_preferences, context)
    renderer    = CalendarTemplateRenderer.new
    title       = resolved_preferences[:title_template].present? ? renderer.render(resolved_preferences[:title_template], context) : context[:title]
    description = resolved_preferences[:description_template].present? ? renderer.render(resolved_preferences[:description_template], context) : ""
    location    = resolved_preferences[:location_template].present? ? renderer.render(resolved_preferences[:location_template], context) : (context[:location] || "")
    { title: title, description: description, location: location }
  end
end
