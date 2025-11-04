# frozen_string_literal: true

module Admin
  class CalendarsController < Admin::BaseController
    def index
      @calendars = GoogleCalendarService.new.list_calendars.items
    end

    def destroy
      # Enqueue job to delete calendar
      GoogleCalendarDeleteJob.perform_later(params[:id])
      redirect_to admin_calendars_path, notice: "Calendar deletion job enqueued."
    rescue => e
      redirect_to admin_calendars_path, alert: "Failed to enqueue calendar deletion: #{e.message}"
    end

  end
end
