# frozen_string_literal: true

module CourseCalendars
  # The users whose calendars need a sync when data that many users share
  # changes: finals, holidays, or other university events.
  module ResyncAudience
    def self.all
      User.with_course_calendar
    end

    # The users with a course in the term, for a change to its finals.
    def self.enrolled_in(term_id)
      all.where(id: Enrollment.joins(:course).where(courses: { term_id: term_id }).select(:user_id))
    end

    # The users who show university events in their calendars.
    def self.with_university_events
      all.joins(:user_extension_config).where(user_extension_configs: { sync_university_events: true })
    end
  end
end
