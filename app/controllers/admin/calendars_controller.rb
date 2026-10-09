# frozen_string_literal: true

module Admin
  class CalendarsController < Admin::ApplicationController
    def index
      @calendars = policy_scope(CourseCalendar)
                   .includes(:oauth_credential, :user)
                   .order(updated_at: :desc)

      if params[:search].present?
        query = "%#{CourseCalendar.sanitize_sql_like(params[:search].strip)}%"
        @calendars = @calendars.joins(oauth_credential: :user)
                               .where("users.email ILIKE :q OR oauth_credentials.email ILIKE :q", q: query)
      end
      @calendars = @calendars.where(provider: params[:provider]) if params[:provider].present?

      @calendars = @calendars.page(params[:page]).per(25)
    end

    def destroy
      calendar = CourseCalendar.find(params[:id])
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
