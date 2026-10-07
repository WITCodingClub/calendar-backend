# frozen_string_literal: true

# Processes the courses of one term for a user, outside the request.
# POST /api/process_courses/batch enqueues one job for each term after the
# first. One job runs at a time for each user, so a large batch does not send
# many Banner lookups at the same time.
class ProcessTermCoursesJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(user, _courses) { "process_term_courses_user_#{user.id}" }

  retry_on LeopardWebService::RequestError, LeopardWebService::SessionError, Faraday::Error,
           wait: :polynomially_longer, attempts: 3

  # A bad payload or a missing term does not get better on a retry.
  discard_on ArgumentError, InvalidTermError

  def perform(user, courses)
    CourseProcessorService.new(courses, user).call
  end
end
