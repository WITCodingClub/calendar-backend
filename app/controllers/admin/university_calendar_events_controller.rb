# frozen_string_literal: true

module Admin
  class UniversityCalendarEventsController < Admin::ApplicationController
    def index
      @university_calendar_events = policy_scope(UniversityCalendarEvent)
                                    .includes(:term)
                                    .order(start_time: :desc)

      # Determine if we should show events without location
      @show_all = params[:show_all] == "1"
      @category_filter = params[:category].presence

      # When filtering by category, show all events in that category (bypass location filter)
      # Otherwise, by default hide events without a location (unless explicitly showing all)
      unless @show_all || @category_filter
        @university_calendar_events = @university_calendar_events.with_location
      end

      # Search filter
      if params[:search].present?
        @university_calendar_events = @university_calendar_events
                                      .where("summary ILIKE ? OR description ILIKE ?",
                                             "%#{params[:search]}%", "%#{params[:search]}%")
      end

      # Category filter
      if @category_filter
        @university_calendar_events = @university_calendar_events.where(category: @category_filter)
      end

      # Stats for dashboard - category counts show ALL events in each category (regardless of location)
      # so clicking a category link shows all events that match that count
      base_scope = @show_all ? UniversityCalendarEvent.all : UniversityCalendarEvent.with_location

      @stats = {
        total: base_scope.count,
        holidays: base_scope.holidays.count,
        upcoming: base_scope.upcoming.count,
        categories: UniversityCalendarEvent.group(:category).count # Always show true category counts
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
