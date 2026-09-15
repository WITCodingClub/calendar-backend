# frozen_string_literal: true

module Admin
  class CalendarEventsController < Admin::ApplicationController
    def index
      authorize CalendarEvent
      @calendar_events = policy_scope(CalendarEvent)
                                .includes(:course_calendar, :meeting_time)
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(25)
    end
  end
end
