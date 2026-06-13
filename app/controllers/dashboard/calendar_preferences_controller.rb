# frozen_string_literal: true

class Dashboard::CalendarPreferencesController < Dashboard::ApplicationController
  include PreferenceParams

  before_action :set_calendar_preference, only: [:update]

  def index
    authorize current_user, :show?

    preferences       = policy_scope(current_user.calendar_preferences)
    @global_pref      = preferences.find_by(scope: :global)
    @event_type_prefs = preferences.where(scope: :event_type)
    @uni_cal_prefs    = preferences.where(scope: :uni_cal_category)
    @global_pref    ||= current_user.calendar_preferences.build(scope: :global)
  end

  def update
    authorize @calendar_preference

    if @calendar_preference.update(calendar_preference_params)
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_calendar_preferences_path, notice: "Preferences saved."
    else
      redirect_to dashboard_calendar_preferences_path,
                  alert: @calendar_preference.errors.full_messages.to_sentence
    end
  end

  private

  def set_calendar_preference
    scope_param = params[:id]

    @calendar_preference = if scope_param == "global"
                              current_user.calendar_preferences.find_or_initialize_by(scope: :global)
                            elsif scope_param.to_s.start_with?("uni_cal:")
                              category = scope_param.delete_prefix("uni_cal:")
                              current_user.calendar_preferences.find_or_initialize_by(
                                scope: :uni_cal_category, event_type: category
                              )
                            else
                              current_user.calendar_preferences.find_or_initialize_by(
                                scope: :event_type, event_type: scope_param
                              )
                            end
  end
end
