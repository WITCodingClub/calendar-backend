# frozen_string_literal: true

module McpTools
  # The courses of the signed-in user in one term, with weekly meeting times.
  # The data is the same as GET /api/user/processed_events, without the
  # calendar event settings.
  class MyCourses < BaseTool
    tool_name "my_courses"
    title "My courses"
    description "Lists my Wentworth (WIT) classes in one term, with the professor and the weekly meeting " \
                "times and rooms. Use it for \"what classes do I have today\", \"where is my next class\", " \
                "\"who is my professor\", and \"what is my schedule\". Times are 24-hour, in the America/New_York " \
                "time zone."
    requires_scope "schedule:read"
    academic_planning :sections
    # Hosts with the MCP Apps extension show the result as a week grid.
    meta WeekGridApp.tool_meta
    input_schema(properties: { term_uid: TERM_SCHEMA })
    # Only for a term that the schedule page lists. A past term or a term
    # with no courses gets no link, because the page would not show it.
    links do |result|
      next [] unless ScheduleLoading.terms_for(user).pluck(:uid).include?(result[:term_uid])

      [
        onboarded_page_link(
          name:        "wit-calendar-schedule",
          title:       "My schedule on WIT Calendar",
          url:         page_url(:dashboard_schedule_url, term_uid: result[:term_uid]),
          description: "Your courses in #{result[:term_name]}, as a list, a week, or a month."
        )
      ]
    end
    output_schema(
      Schemas.object(term_uid: Schemas::INTEGER, term_name: Schemas::STRING, courses: Schemas.array(Schemas::MY_COURSE))
    )

    def perform(term_uid: nil)
      authorize user, :show?
      term = find_term(term_uid)

      classes = Courses::ProcessedEventsBuilder.new(user, term).build[:classes].map do |course|
        course.merge(meeting_times: course[:meeting_times].map { |time| time.except(:calendar_config) })
      end

      refresh_stale_sections(term.uid, classes.pluck(:crn))
      { term_uid: term.uid, term_name: term.name, courses: classes }
    end
  end
end
