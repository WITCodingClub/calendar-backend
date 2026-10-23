# frozen_string_literal: true

module McpTools
  class UniversityEvents < BaseTool
    DEFAULT_LIMIT = 25
    MAX_LIMIT     = 100

    tool_name "university_events"
    title "University calendar events"
    description "Lists Wentworth academic calendar events: holidays, term dates, registration, deadlines, " \
                "study days, finals, and graduation. Without dates it lists upcoming events."
    requires_scope "catalog"
    academic_planning :university_calendar
    input_schema(
      properties: {
        start_date: DATE_SCHEMA,
        end_date:   DATE_SCHEMA,
        categories: {
          type:  "array",
          items: { type: "string", enum: UniversityCalendarEvent::SYNCABLE_CATEGORIES }
        },
        limit:      { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Most events to return. Default #{DEFAULT_LIMIT}." }
      }
    )

    def perform(start_date: nil, end_date: nil, categories: nil, limit: nil)
      authorize UniversityCalendarEvent, :index?
      events = Pundit.policy_scope!(user, UniversityCalendarEvent).includes(:term).order(:start_time)

      events = if start_date || end_date
        from = start_date ? parse_date(start_date, "start_date") : Time.zone.today
        to   = end_date ? parse_date(end_date, "end_date") : from.next_year
        raise ToolError, "end_date must not be before start_date" if to < from

        events.in_date_range(from, to)
      else
        events.upcoming
      end

      events = events.by_categories(categories) if categories.present?
      events = events.limit(limit_value(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT))

      { events: events.map { |event| UniversityCalendarEventSerializer.new(event).as_json } }
    end
  end
end
