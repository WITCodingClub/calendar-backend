# frozen_string_literal: true

# Processes the course payloads of several terms from one request.
#
# Each term gets its own result, so a failure in one term never fails the
# others. Only the first term is processed inside the request. The other terms
# go to ProcessTermCoursesJob and come back as "pending": process_courses calls
# Banner for each CRN (#683), and doing that for every term would hold a Puma
# thread for too long. The extension polls /api/user/is_processed for the
# pending terms.
class CourseBatchProcessorService < ApplicationService
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
      term_uid, courses, error = prepare(entry)
      next Result.new(term: term_uid, status: FAILED, error: error) if error

      unless seen.add?(term_uid)
        next Result.new(term: term_uid, status: FAILED, error: "Term #{term_uid} appears more than once in the batch")
      end

      if processed_inline
        ProcessTermCoursesJob.perform_later(user, courses)
        next Result.new(term: term_uid, status: PENDING)
      end

      processed_inline = true
      process_now(term_uid, courses)
    end
  end

  private

  # Returns [term_uid, courses, error]. Courses without a term get the term of
  # their entry, so the extension does not have to repeat it.
  def prepare(entry)
    return [ nil, nil, "Each term entry must be an object" ] unless entry.is_a?(Hash)

    term_uid = entry[:term].to_s
    return [ term_uid.presence, nil, "Term entry is missing a numeric term" ] unless term_uid.match?(/\A\d+\z/)

    courses = entry[:courses]
    return [ term_uid, nil, "Term #{term_uid} has no courses" ] unless courses.is_a?(Array) && courses.any?

    courses = courses.map do |course|
      next course unless course.is_a?(Hash)

      course = course.with_indifferent_access
      course[:term] = term_uid if course[:term].blank?
      course
    end

    if courses.any? { |course| course.is_a?(Hash) && course[:term].to_s != term_uid }
      return [ term_uid, nil, "All courses in term #{term_uid} must belong to that term" ]
    end

    return [ term_uid, nil, "Term #{term_uid} not found" ] unless Term.exists?(uid: term_uid)

    CourseProcessorService.new(courses, user).validate!
    [ term_uid, courses, nil ]
  rescue ArgumentError => e
    [ term_uid, nil, e.message ]
  end

  def process_now(term_uid, courses)
    processed = CourseProcessorService.new(courses, user).call
    Result.new(term: term_uid, status: PROCESSED, course_count: processed.size)
  rescue ArgumentError, InvalidTermError => e
    Result.new(term: term_uid, status: FAILED, error: e.message)
  rescue => e
    Rails.logger.error("[CourseBatchProcessorService] Term #{term_uid} failed: #{e.class} - #{e.message}")
    Result.new(term: term_uid, status: FAILED, error: "Failed to process courses")
  end
end
