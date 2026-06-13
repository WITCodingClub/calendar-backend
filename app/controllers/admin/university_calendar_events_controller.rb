# frozen_string_literal: true

module Admin
  class UniversityCalendarEventsController < Admin::ApplicationController
    def index
      @university_calendar_events = policy_scope(UniversityCalendarEvent)
                                    .includes(:term)
                                    .order(start_time: :desc)

      @show_all        = params[:show_all] == "1"
      @category_filter = params[:category].presence

      unless @show_all || @category_filter
        @university_calendar_events = @university_calendar_events.with_location
      end

      if params[:search].present?
        @university_calendar_events = @university_calendar_events
                                      .where("summary ILIKE ? OR description ILIKE ?",
                                             "%#{params[:search]}%", "%#{params[:search]}%")
      end

      if @category_filter
        @university_calendar_events = @university_calendar_events.where(category: @category_filter)
      end

      base_scope = @show_all ? UniversityCalendarEvent.all : UniversityCalendarEvent.with_location

      @stats = {
        total:      base_scope.count,
        holidays:   base_scope.holidays.count,
        upcoming:   base_scope.upcoming.count,
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

    def backfill
      authorize UniversityCalendarEvent

      start_date = Date.parse(params[:start_date])
      end_date   = Date.parse(params[:end_date])

      if end_date < start_date
        redirect_to admin_university_calendar_events_path, alert: "End date must be on or after start date."
        return
      end

      UniversityCalendarBackfillJob.perform_later(start_date.to_s, end_date.to_s)
      redirect_to admin_university_calendar_events_path,
                  notice: "Backfill queued for #{start_date.strftime('%b %d, %Y')} – #{end_date.strftime('%b %d, %Y')}."
    rescue Date::Error
      redirect_to admin_university_calendar_events_path, alert: "Invalid date format."
    end
  end
end
