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
    input_schema(properties: { term_uid: TERM_SCHEMA })

    def perform(term_uid: nil)
      authorize user, :show?
      term = find_term(term_uid)

      classes = Courses::ProcessedEventsBuilder.new(user, term).build[:classes].map do |course|
        course.merge(meeting_times: course[:meeting_times].map { |time| time.except(:calendar_config) })
      end

      { term_uid: term.uid, courses: classes }
    end
  end
end
