# frozen_string_literal: true

module Admin
  class CalendarsController < Admin::ApplicationController
    def index
      @calendars = policy_scope(CourseCalendar)
                   .includes(:oauth_credential, :user)
                   .left_joins(:calendar_events)
                   .select("calendars.*, MAX(calendar_events.updated_at) as max_event_updated_at")
                   .group("calendars.id")
                   .order(updated_at: :desc)
                   .page(params[:page]).per(7)
    end

    def destroy
      calendar = CourseCalendar.find(params[:id])
      authorize calendar

      # The row's own callback deletes the remote calendar with the right
      # provider. A Google delete job here would get a Microsoft calendar id.
      calendar.destroy
      redirect_to admin_calendars_path, notice: "Calendar deleted successfully."
    rescue => e
      redirect_to admin_calendars_path, alert: "Failed to delete calendar: #{e.message}"
    end
  end
end
