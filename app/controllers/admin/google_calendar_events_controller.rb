# frozen_string_literal: true

module Admin
  class GoogleCalendarEventsController < Admin::ApplicationController
    def index
      @google_calendar_events = GoogleCalendarEvent.includes(:google_calendar, :meeting_time).order(created_at: :desc).page(params[:page]).per(6)
    end

  end
end
