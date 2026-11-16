# frozen_string_literal: true

module Courses
  # One user's courses in one term, as EnrolledCourseSerializer hashes with
  # that user's own preferences. The extension's course list
  # (Api::ProcessedEventsController) and the dashboard schedule both show it,
  # so a friend's schedule looks the same as in the friend's own calendar.
  module EnrolledCourses
    def self.for(user, term)
      enrollments = user.enrollments.where(term_id: term.id).includes(ProcessedEventsBuilder::ENROLLMENT_INCLUDES)
      resolver    = Preferences::Resolver.new(user)
      renderer    = Preferences::TemplateRenderer.new(user_id: user.id)
      recurrence  = CourseCalendars::RecurrenceBuilder.preloaded(user, enrollments.map(&:course))

      enrollments.map do |enrollment|
        EnrolledCourseSerializer.new(enrollment, term: term, preference_resolver: resolver,
                                                 template_renderer: renderer, recurrence: recurrence).as_json
      end
    end
  end
end
