# frozen_string_literal: true

# The strong parameters of the calendar and event preference controllers,
# for the API and the dashboard forms, so both read reminders the same way.
module PreferenceParams
  extend ActiveSupport::Concern

  # Sent instead of a reminder list to drop an override and fall back to the
  # level below it. An empty list means "no reminders", which is not the same.
  RESET_REMINDER_SETTINGS = "default"

  private

  def calendar_preference_params = preference_params(:calendar_preference)
  def event_preference_params    = preference_params(:event_preference)

  def preference_params(key)
    permitted = require_object_param(key).permit(
      :title_template, :description_template, :location_template,
      :color_id, :visibility, reminder_settings: []
    )
    apply_reminder_settings(permitted, params[key])
    permitted
  end

  # params.require returns a String when a client sends a scalar. Reject it
  # as a bad request, which the API and the web controllers answer with 400.
  def require_object_param(key)
    value = params.require(key)
    return value if value.is_a?(ActionController::Parameters)

    raise ActionController::BadRequest, "#{key} must be an object"
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
end
