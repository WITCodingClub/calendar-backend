# frozen_string_literal: true

class Dashboard::CalendarPreferencesController < Dashboard::ApplicationController
  include PreferenceParams

  before_action :set_calendar_preference, only: [ :update ]

  def index
    authorize current_user, :show?

    preferences        = policy_scope(current_user.calendar_preferences)
    @global_pref       = preferences.find_by(scope: :global)
    @uni_cal_pref      = preferences.find_by(scope: :uni_cal_global)
    @event_type_prefs  = preferences.where(scope: :event_type)
    @uni_cal_prefs     = preferences.where(scope: :uni_cal_category)
    @global_pref     ||= current_user.calendar_preferences.build(scope: :global)
    @uni_cal_pref    ||= current_user.calendar_preferences.build(scope: :uni_cal_global)
    @extension_config  = current_user.user_extension_config || current_user.build_user_extension_config
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

  # Turns university event sync on or off and sets the categories to sync.
  # The categories stay stored while sync is off, so turning it on again restores them.
  # UserExtensionConfig queues the calendar sync when either setting changes.
  def university_events
    config = UserExtensionConfig.find_or_create_by!(user: current_user)
    authorize config, :update?

    config.sync_university_events      = params[:sync_university_events] == "1"
    config.university_event_categories =
      Array(params[:university_event_categories]).map(&:to_s) & UniversityCalendarEvent::CATEGORIES

    if config.save
      redirect_to dashboard_calendar_preferences_path, notice: "University event sync saved."
    else
      redirect_to dashboard_calendar_preferences_path, alert: config.errors.full_messages.to_sentence
    end
  end

  private

  def set_calendar_preference
    @calendar_preference = calendar_preference_for_scope(params[:id])
  end
end
