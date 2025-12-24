# frozen_string_literal: true

module Admin
  class UniversityCalendarEventsController < Admin::ApplicationController
    def index
      @university_calendar_events = policy_scope(UniversityCalendarEvent)
                                    .includes(:term)
                                    .order(start_time: :desc)

      # Search filter
      if params[:search].present?
        @university_calendar_events = @university_calendar_events
                                      .where("summary ILIKE ? OR description ILIKE ?",
                                             "%#{params[:search]}%", "%#{params[:search]}%")
      end

      # Category filter
      if params[:category].present?
        @university_calendar_events = @university_calendar_events.where(category: params[:category])
      end

      # Stats for dashboard
      @stats = {
        total: UniversityCalendarEvent.count,
        holidays: UniversityCalendarEvent.holidays.count,
        upcoming: UniversityCalendarEvent.upcoming.count,
        categories: UniversityCalendarEvent.group(:category).count
      }

      @university_calendar_events = @university_calendar_events.page(params[:page]).per(25)
    end

    def show
      @event = UniversityCalendarEvent.find(params[:id])
      authorize @event
    end

    def sync
      authorize UniversityCalendarEvent

      UniversityCalendarSyncJob.perform_later
      redirect_to admin_university_calendar_events_path, notice: "University calendar sync queued successfully."
    end
  end
end
