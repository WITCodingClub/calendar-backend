# frozen_string_literal: true

module Courses
  # Every term the user has processed, newest first, with the courses in each
  # term. GET /api/user/course_history and the my_course_history MCP tool send
  # it. The server knows only the terms that the extension processed, so the
  # history can have gaps.
  class HistoryBuilder
    def initialize(user)
      @user = user
    end

    def build
      terms   = Term.enrolled_for(@user).reverse_chronological.to_a
      classes = ProcessedEventsBuilder.new(@user).classes_by_term(terms)

      { terms: terms.map { |term| term_data(term, classes.fetch(term.id, [])) } }
    end

    private

    def term_data(term, courses)
      {
        uid:     term.uid,
        pub_id:  term.public_id,
        name:    term.name,
        season:  term.season,
        year:    term.year,
        courses: courses.map { |course| course_data(course) }
      }
    end

    # The term is on the parent, and the calendar event settings matter only
    # to the sync, so the history leaves both out.
    def course_data(course)
      course.except(:term).merge(meeting_times: course[:meeting_times].map { |time| time.except(:calendar_config) })
    end
  end
end
