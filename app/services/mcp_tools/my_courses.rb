# frozen_string_literal: true

module McpTools
  # The courses of the signed-in user in one term, with weekly meeting times.
  # The data is the same as GET /api/user/processed_events, without the
  # calendar event settings.
  class MyCourses < BaseTool
    tool_name "my_courses"
    title "My courses"
    description "Lists the courses I am enrolled in for one term, with the professor and the weekly meeting " \
                "times and rooms. Times are 24-hour, in the America/New_York time zone."
    requires_scope "schedule:read"
    academic_planning :sections
    # Hosts with the MCP Apps extension show the result as a week grid.
    meta WeekGridApp.tool_meta
    input_schema(properties: { term_uid: TERM_SCHEMA })
    output_schema(
      Schemas.object(term_uid: Schemas::INTEGER, term_name: Schemas::STRING, courses: Schemas.array(Schemas::MY_COURSE))
    )

    def perform(term_uid: nil)
      authorize user, :show?
      term = find_term(term_uid)

      classes = Courses::ProcessedEventsBuilder.new(user, term).build[:classes].map do |course|
        course.merge(meeting_times: course[:meeting_times].map { |time| time.except(:calendar_config) })
      end

      { term_uid: term.uid, term_name: term.name, courses: classes }
    end
  end
end
