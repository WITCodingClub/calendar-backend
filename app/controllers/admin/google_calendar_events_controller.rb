# frozen_string_literal: true

module Admin
  class GoogleCalendarEventsController < Admin::ApplicationController
    def index
      authorize GoogleCalendarEvent
      @google_calendar_events = policy_scope(GoogleCalendarEvent)
                                .includes(:google_calendar, :meeting_time)
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(25)
    end

  end
end
