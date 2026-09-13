# frozen_string_literal: true

class Dashboard::NotificationsController < Dashboard::ApplicationController
  # Reminder offsets the university event picker offers, in the order shown.
  # Google fires a reminder relative to the start, and an all day event starts
  # at midnight, so the offsets read differently for those. The labels say so.
  UNIVERSITY_EVENT_REMINDER_CHOICES = [
    { label: "15 minutes before",                                    time: "15", type: "minutes" },
    { label: "30 minutes before",                                    time: "30", type: "minutes" },
    { label: "1 hour before",                                        time: "1",  type: "hours" },
    { label: "3 hours before",                                       time: "3",  type: "hours" },
    { label: "6 hours before (6PM the day before, all day events)",  time: "6",  type: "hours" },
    { label: "15 hours before (9AM the day before, all day events)", time: "15", type: "hours" },
    { label: "1 day before (12AM the day before, all day events)",   time: "1",  type: "days" },
    { label: "2 days before",                                        time: "2",  type: "days" },
    { label: "1 week before",                                        time: "7",  type: "days" }
  ].freeze

  before_action :set_university_event_preference, only: [ :show, :university_events ]

  def show
    authorize current_user, :show?
  end

  def update
    authorize current_user, :update?

    if params[:disable] == "true"
      current_user.disable_notifications!
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_notifications_path, notice: "Notifications disabled."
    else
      current_user.enable_notifications!
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_notifications_path, notice: "Notifications enabled."
    end
  end

  # Sets the reminders for every university calendar event, apart from classes.
  def university_events
    authorize @university_event_preference, :update?

    reminders = university_event_reminder_settings
    if reminders == :invalid
      redirect_to dashboard_notifications_path, alert: "Pick a reminder time."
      return
    end

    @university_event_preference.reminder_settings = reminders

    if @university_event_preference.save
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_notifications_path, notice: "University event notifications saved."
    else
      redirect_to dashboard_notifications_path,
                  alert: @university_event_preference.errors.full_messages.to_sentence
    end
  end

  private

  def set_university_event_preference
    @university_event_preference =
      current_user.calendar_preferences.find_or_initialize_by(scope: :uni_cal_global)
  end

  # nil keeps the system default, [] turns the reminders off, and :invalid
  # reports a custom choice that is not on the list.
  def university_event_reminder_settings
    case params[:mode]
    when "off"    then []
    when "custom" then selected_reminder_choice || :invalid
    end
  end

  # The picker sends one reminder as "<time>:<type>", for example "15:hours".
  def selected_reminder_choice
    time, type = params[:reminder].to_s.split(":", 2)
    choice = UNIVERSITY_EVENT_REMINDER_CHOICES.find do |option|
      option[:time] == time && option[:type] == type
    end
    return if choice.nil?

    [ { "time" => choice[:time], "type" => choice[:type], "method" => params[:delivery] == "email" ? "email" : "popup" } ]
  end
end
