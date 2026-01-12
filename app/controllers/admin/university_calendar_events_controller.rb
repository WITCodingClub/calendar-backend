# frozen_string_literal: true

module Admin
  class UniversityCalendarEventsController < Admin::ApplicationController
    def index
      @university_calendar_events = policy_scope(UniversityCalendarEvent)
                                    .includes(:term)
                                    .order(start_time: :desc)

      # Determine if we should show events without location
      @show_all = params[:show_all] == "1"

      # By default, hide events without a location (unless explicitly showing all)
      @university_calendar_events = @university_calendar_events.with_location unless @show_all

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

      # Stats for dashboard - respect the same location filter as the main listing
      base_scope = @show_all ? UniversityCalendarEvent.all : UniversityCalendarEvent.with_location

      @stats = {
        total: base_scope.count,
        holidays: base_scope.holidays.count,
        upcoming: base_scope.upcoming.count,
        categories: base_scope.group(:category).count
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
