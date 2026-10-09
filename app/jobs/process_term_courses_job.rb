# frozen_string_literal: true

# Processes the courses of one term for a user, outside the request.
# POST /api/process_courses/batch enqueues one job for each term after the
# first. One job runs at a time for each user, so a large batch does not send
# many Banner lookups at the same time.
#
# The job keeps the term's TermProcessingStatus current, so the extension can
# poll /api/user/processed_events/status: "processing" while it runs, "processed" when
# CourseProcessorService is done, and "failed" with an error code when the
# term cannot be processed.
class ProcessTermCoursesJob < ApplicationJob
  queue_as :default

  RETRYABLE_ERRORS = [ LeopardWebService::RequestError, LeopardWebService::SessionError, Faraday::Error ].freeze

  # The concurrency group is part of every lock key, so it must not change when
  # the class is renamed. Jobs in the queue hold locks under this name.
  CONCURRENCY_GROUP = "ProcessTermCoursesJob"

  limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, _term, _courses) { "process_term_courses_user_#{user.id}" }

  # After the last attempt, record the failure and raise again, so the job
  # stays in the failed-jobs list.
  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
    job.mark_failed(:banner_unavailable)
    raise error
  end

  # A missing term does not get better on a retry.
  discard_on(InvalidTermError) { |job, _error| job.mark_failed(:term_not_found) }

  def perform(user, term, courses)
    TermProcessingStatus.record!(user, term, :processing)

    # CourseProcessorService marks the term processed when it enrolls at
    # least one course.
    processed = CourseProcessorService.new(courses, user).call
    mark_failed(:no_course_details) if processed.empty?
  rescue *RETRYABLE_ERRORS, InvalidTermError
    raise
  rescue StandardError
    # Any other error is a bug. Do not retry, but tell the extension the term
    # failed and keep the job in the failed-jobs list.
    mark_failed(:internal_error)
    raise
  end

  def mark_failed(error_code)
    user, term, = arguments
    TermProcessingStatus.record!(user, term, :failed, error_code: error_code)
  end
end
