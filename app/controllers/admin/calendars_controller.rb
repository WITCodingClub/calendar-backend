# frozen_string_literal: true

module Admin
  class CalendarsController < Admin::BaseController
    def index
      # Get calendars from the database with associations
      @calendars = GoogleCalendar
                   .includes(:oauth_credential, :user)
                   .left_joins(:google_calendar_events)
                   .select("google_calendars.*, MAX(google_calendar_events.updated_at) as max_event_updated_at")
                   .group("google_calendars.id")
                   .order(updated_at: :desc)
                   .map do |calendar|
        {
          id: calendar.id,
          google_calendar_id: calendar.google_calendar_id,
          summary: calendar.summary || "WIT Courses",
          user: calendar.user,
          user_email: calendar.oauth_credential&.email,
          last_updated: calendar.max_event_updated_at || calendar.updated_at
        }
      end
    end

    def destroy
      calendar = GoogleCalendar.find(params[:id])
      # Enqueue job to delete calendar from Google
      GoogleCalendarDeleteJob.perform_later(calendar.google_calendar_id)
      # Delete the database record
      calendar.destroy
      redirect_to admin_calendars_path, notice: "Calendar deleted successfully."
    rescue => e
      redirect_to admin_calendars_path, alert: "Failed to delete calendar: #{e.message}"
    end

  end
end
