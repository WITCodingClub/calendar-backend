# frozen_string_literal: true

module Api
  class UniversityCalendarEventsController < ApiController
    before_action :set_event, only: [:show]

    # GET /api/university_calendar_events
    # List upcoming university calendar events
    # Optional filters: category, start_date, end_date, term_id
    def index
      @events = policy_scope(UniversityCalendarEvent)
                .upcoming
                .order(:start_time)

      # Filter by category
      if params[:category].present?
        @events = @events.where(category: params[:category])
      end

      # Filter by categories (array)
      if params[:categories].present?
        categories = params[:categories].is_a?(Array) ? params[:categories] : params[:categories].split(",")
        @events = @events.by_categories(categories)
      end

      # Filter by date range
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @events = @events.in_date_range(start_date, end_date)
      end

      # Filter by term
      if params[:term_id].present?
        @events = @events.for_term(Term.find_by_public_id(params[:term_id]))
      end

      # Pagination
      @events = @events.page(params[:page]).per(params[:per_page] || 25)

      render json: {
        events: @events.map { |e| UniversityCalendarEventSerializer.new(e).as_json },
        meta: pagination_meta(@events)
      }
    end

    # GET /api/university_calendar_events/:id
    def show
      authorize @event
      render json: { event: UniversityCalendarEventSerializer.new(@event).as_json }
    end

    # GET /api/university_calendar_events/categories
    # List available event categories
    def categories
      authorize UniversityCalendarEvent, :index?

      render json: {
        categories: UniversityCalendarEvent::CATEGORIES.map do |category|
          {
            id: category,
            name: category.titleize,
            count: UniversityCalendarEvent.where(category: category).count
          }
        end
      }
    end

    # GET /api/university_calendar_events/holidays
    # List holidays, optionally filtered by term or date range
    def holidays
      authorize UniversityCalendarEvent, :index?

      @holidays = UniversityCalendarEvent.holidays.upcoming.order(:start_time)

      # Filter by term
      if params[:term_id].present?
        term = Term.find_by_public_id(params[:term_id])
        @holidays = @holidays.for_term(term) if term
      end

      # Filter by date range
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @holidays = @holidays.in_date_range(start_date, end_date)
      end

      render json: {
        holidays: @holidays.map { |h| UniversityCalendarEventSerializer.new(h).as_json }
      }
    end

    # POST /api/university_calendar_events/sync (admin only)
    # Trigger a sync from the ICS feed
    def sync
      authorize UniversityCalendarEvent

      UniversityCalendarSyncJob.perform_later
      render json: { message: "University calendar sync queued" }
    end

    private

    def set_event
      @event = UniversityCalendarEvent.find_by_public_id(params[:id])
      raise ActiveRecord::RecordNotFound, "UniversityCalendarEvent not found" unless @event
    end

    def pagination_meta(collection)
      {
        current_page: collection.current_page,
        total_pages: collection.total_pages,
        total_count: collection.total_count,
        per_page: collection.limit_value
      }
    end

  end
end
