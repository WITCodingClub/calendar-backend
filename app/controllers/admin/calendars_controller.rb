# frozen_string_literal: true

module Admin
  class CalendarsController < Admin::ApplicationController
    def index
      authorize CourseCalendar
      @calendars = policy_scope(CourseCalendar)
                   .includes(:oauth_credential, :user)
                   .order(updated_at: :desc)

      if params[:search].present?
        @calendars = search_scope(@calendars.joins(oauth_credential: :user), "users.email", "oauth_credentials.email")
      end
      @calendars = @calendars.where(provider: params[:provider]) if params[:provider].present?

      @calendars = @calendars.page(params[:page]).per(25)
    end

    def destroy
      calendar = policy_scope(CourseCalendar).find(params[:id])
      authorize calendar

      # The row's own callback deletes the remote calendar with the right
      # provider. A Google delete job here would get a Microsoft calendar id.
      calendar.destroy
      redirect_to admin_calendars_path, notice: "Calendar deleted successfully."
    rescue => e
      Rails.error.report(e, handled: true, context: { course_calendar_id: params[:id] })
      redirect_to admin_calendars_path, alert: "Failed to delete calendar: #{e.message}"
    end
  end
end
