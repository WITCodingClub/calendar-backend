# frozen_string_literal: true

module Courses
  # Processes the course payloads of several terms from one request.
  #
  # Each term gets its own result, so a failure in one term never fails the
  # others. Only the first term is processed inside the request. The other terms
  # go to Courses::ProcessTermJob and come back as "pending": process_courses calls
  # Banner for each CRN (#683), and doing that for every term would hold a Puma
  # thread for too long. The extension polls /api/user/processed_events/status for the
  # pending terms.
  #
  # A term that already has a job in flight (status "pending" or "processing")
  # is never processed inside the request. It goes to the job queue again, so
  # the request and a job never process the same term for the same user at the
  # same time. The job's per-user concurrency key runs the queued jobs in order.
  class BatchProcessor < ApplicationService
    MAX_TERMS = 12

    PROCESSED = "processed"
    PENDING   = "pending"
    FAILED    = "failed"

    Result = Struct.new(:term, :status, :course_count, :error, keyword_init: true)

    attr_reader :entries, :user

    # entries: an array of { term: "202710", courses: [ {...}, ... ] } hashes.
    def initialize(entries, user)
      @entries = entries
      @user = user
      super()
    end

    def call
      seen = Set.new
      processed_inline = false

      entries.map do |entry|
        term_uid, term, courses, error = prepare(entry)
        next Result.new(term: term_uid, status: FAILED, error: error) if error

        unless seen.add?(term_uid)
          next Result.new(term: term_uid, status: FAILED, error: "Term #{term_uid} appears more than once in the batch")
        end

        if processed_inline || in_flight?(term)
          next enqueue(term_uid, term, courses)
        end

        processed_inline = true
        process_now(term_uid, term, courses)
      end
    end

    private

    # Returns [term_uid, term, courses, error]. Courses without a term get the term of
    # their entry, so the extension does not have to repeat it.
    def prepare(entry)
      return [ nil, nil, nil, "Each term entry must be an object" ] unless entry.is_a?(Hash)

      term_uid = entry[:term].to_s
      return [ term_uid.presence, nil, nil, "Term entry is missing a numeric term" ] unless term_uid.match?(/\A\d+\z/)

      courses = entry[:courses]
      return [ term_uid, nil, nil, "Term #{term_uid} has no courses" ] unless courses.is_a?(Array) && courses.any?

      courses = courses.map do |course|
        next course unless course.is_a?(Hash)

        course = course.with_indifferent_access
        course[:term] = term_uid if course[:term].blank?
        course
      end

      if courses.any? { |course| course.is_a?(Hash) && course[:term].to_s != term_uid }
        return [ term_uid, nil, nil, "All courses in term #{term_uid} must belong to that term" ]
      end

      term = terms_by_uid[term_uid]
      return [ term_uid, nil, nil, "Term #{term_uid} not found" ] unless term

      Courses::Processor.new(courses, user).validate!
      [ term_uid, term, courses, nil ]
    rescue ArgumentError => e
      [ term_uid, nil, nil, e.message ]
    end

    # One query for all terms of the batch, not one per entry.
    def terms_by_uid
      @terms_by_uid ||= begin
        uids = entries.filter_map { |entry| entry[:term].to_s if entry.is_a?(Hash) }.uniq
        Term.where(uid: uids).index_by { |term| term.uid.to_s }
      end
    end

    def in_flight?(term)
      @in_flight_term_ids ||= TermProcessingStatus.where(user: user, term: terms_by_uid.values, status: %w[pending processing]).pluck(:term_id).to_set
      @in_flight_term_ids.include?(term.id)
    end

    def enqueue(term_uid, term, courses)
      TermProcessingStatus.record!(user, term, :pending)
      Courses::ProcessTermJob.perform_later(user, term, courses)
      Result.new(term: term_uid, status: PENDING)
    end

    def process_now(term_uid, term, courses)
      TermProcessingStatus.record!(user, term, :processing)

      # Courses::Processor marks the term processed when it enrolls at least
      # one course.
      processed = Courses::Processor.new(courses, user).call
      if processed.empty?
        return fail_term(term_uid, term, :no_course_details, "No course details found for term #{term_uid}")
      end

      Result.new(term: term_uid, status: PROCESSED, course_count: processed.size)
    rescue Courses::InvalidTermError => e
      fail_term(term_uid, term, :term_not_found, e.message)
    rescue *Courses::ProcessTermJob::RETRYABLE_ERRORS => e
      log_failure(term_uid, e)
      fail_term(term_uid, term, :banner_unavailable, "Failed to process courses")
    rescue => e
      log_failure(term_uid, e)
      fail_term(term_uid, term, :internal_error, "Failed to process courses")
    end

    def fail_term(term_uid, term, error_code, message)
      TermProcessingStatus.record!(user, term, :failed, error_code: error_code)
      Result.new(term: term_uid, status: FAILED, error: message)
    end

    def log_failure(term_uid, error)
      Rails.logger.error("[Courses::BatchProcessor] Term #{term_uid} failed: #{error.class} - #{error.message}")
    end
  end
end
