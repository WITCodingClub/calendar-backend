# frozen_string_literal: true

class CourseDataSyncJob < ApplicationJob
  include ApplicationHelper

  queue_as :low

  # Run with low concurrency to avoid overwhelming LeopardWeb API
  limits_concurrency to: 1, key: -> { "course_data_sync" }

  # Sync course data for current and next term by default
  def perform(term_uids: nil)
    term_uids ||= default_term_uids

    return if term_uids.empty?

    Rails.logger.info "CourseDataSyncJob: Starting sync for terms: #{term_uids}"

    term_uids.each do |term_uid|
      sync_term_courses(term_uid)
    end

    Rails.logger.info "CourseDataSyncJob: Completed sync for #{term_uids.length} terms"
  end

  private

  def default_term_uids
    uids = []
    uids << Term.current_uid if Term.current_uid
    uids << Term.next_uid if Term.next_uid
    uids.compact.uniq
  end

  def sync_term_courses(term_uid)
    term = Term.find_by(uid: term_uid)
    unless term
      Rails.logger.warn "CourseDataSyncJob: Term not found for UID #{term_uid}"
      return
    end

    Rails.logger.info "CourseDataSyncJob: Syncing courses for term #{term.name} (#{term_uid})"

    courses = term.courses.includes(:meeting_times, meeting_times: [:room, :building])
    synced_count = 0
    error_count = 0

    courses.find_each(batch_size: 50) do |course|
      begin
        if sync_course_data(course, term_uid)
          synced_count += 1
        end

        # Rate limiting - small delay between API calls
        sleep(0.1)
      rescue => e
        error_count += 1
        Rails.logger.error "CourseDataSyncJob: Failed to sync course #{course.crn}: #{e.message}"

        # Continue with other courses even if one fails
        next
      end
    end

    Rails.logger.info "CourseDataSyncJob: Term #{term.name} sync complete - #{synced_count} courses synced, #{error_count} errors"
  end

  def sync_course_data(course, term_uid)
    # Fetch fresh data from LeopardWeb
    fresh_data = fetch_fresh_course_data(course.crn, term_uid)
    return false unless fresh_data

    # Check if course-level data changed
    course_changed = course_data_changed?(course, fresh_data)

    # Check if meeting times/locations changed
    meeting_times_changed = meeting_times_changed?(course, fresh_data)

    # Update course if any changes detected
    if course_changed || meeting_times_changed
      update_course_from_fresh_data(course, fresh_data, term_uid)
      Rails.logger.info "CourseDataSyncJob: Updated course #{course.crn} due to changes"
      return true
    end

    false
  end

  def fetch_fresh_course_data(crn, term_uid)
    LeopardWebService.get_class_details(
      term: term_uid,
      course_reference_number: crn
    )
  rescue => e
    Rails.logger.error "CourseDataSyncJob: Failed to fetch data for CRN #{crn}: #{e.message}"
    nil
  end

  def course_data_changed?(course, fresh_data)
    # Parse fresh data and normalize for comparison
    fresh_title = fresh_data[:title].present? ? titleize_with_roman_numerals(fresh_data[:title].strip) : nil
    fresh_credit_hours = fresh_data[:credit_hours]
    fresh_grade_mode = fresh_data[:grade_mode]&.strip
    fresh_subject = fresh_data[:subject]&.strip
    fresh_section_number = normalize_section_number(fresh_data[:section_number])

    # Extract schedule type from format like "Lecture (LEC)"
    fresh_schedule_type = nil
    if fresh_data[:schedule_type]
      schedule_match = fresh_data[:schedule_type].to_s.match(/\(([^)]+)\)/)
      fresh_schedule_type = schedule_match ? schedule_match[1].strip : fresh_data[:schedule_type]&.strip
    end

    # Compare all course attributes that could change
    changes = []

    if course.title != fresh_title
      changes << "title: '#{course.title}' -> '#{fresh_title}'"
    end

    if course.credit_hours != fresh_credit_hours
      changes << "credit_hours: #{course.credit_hours} -> #{fresh_credit_hours}"
    end

    if course.grade_mode != fresh_grade_mode
      changes << "grade_mode: '#{course.grade_mode}' -> '#{fresh_grade_mode}'"
    end

    if course.subject != fresh_subject
      changes << "subject: '#{course.subject}' -> '#{fresh_subject}'"
    end

    if course.section_number != fresh_section_number
      changes << "section_number: '#{course.section_number}' -> '#{fresh_section_number}'"
    end

    if fresh_schedule_type && course.schedule_type != fresh_schedule_type
      changes << "schedule_type: '#{course.schedule_type}' -> '#{fresh_schedule_type}'"
    end

    if changes.any?
      Rails.logger.info "CourseDataSyncJob: Course #{course.crn} changes detected: #{changes.join(', ')}"
      true
    else
      false
    end
  end

  def meeting_times_changed?(course, fresh_data)
    # This is a simplified check - in practice, you might want to compare
    # the full meeting times structure from LeopardWeb

    # For now, we'll assume meeting times come from the course processor
    # and check if the course has any meeting times without proper location data
    course.meeting_times.any? do |mt|
      mt.room.number.zero? || mt.building.abbreviation == "TBD"
    end
  end

  def update_course_from_fresh_data(course, fresh_data, term_uid)
    # Parse and normalize fresh data
    fresh_title = fresh_data[:title].present? ? titleize_with_roman_numerals(fresh_data[:title].strip) : nil
    fresh_credit_hours = fresh_data[:credit_hours]
    fresh_grade_mode = fresh_data[:grade_mode]&.strip
    fresh_subject = fresh_data[:subject]&.strip
    fresh_section_number = normalize_section_number(fresh_data[:section_number])

    # Extract schedule type
    fresh_schedule_type = nil
    if fresh_data[:schedule_type]
      schedule_match = fresh_data[:schedule_type].to_s.match(/\(([^)]+)\)/)
      fresh_schedule_type = schedule_match ? schedule_match[1].strip : fresh_data[:schedule_type]&.strip
    end

    # Build update attributes hash
    update_attrs = {}

    update_attrs[:title] = fresh_title if fresh_title
    update_attrs[:credit_hours] = fresh_credit_hours if fresh_credit_hours
    update_attrs[:grade_mode] = fresh_grade_mode if fresh_grade_mode
    update_attrs[:subject] = fresh_subject if fresh_subject
    update_attrs[:section_number] = fresh_section_number if fresh_section_number
    update_attrs[:schedule_type] = fresh_schedule_type if fresh_schedule_type

    # Update course with changed attributes
    course.update!(update_attrs) if update_attrs.any?

    # Note: For meeting time/location updates, we'd need to implement logic similar to
    # CourseProcessorService or MeetingTimesIngestService. This would require additional
    # API calls to get full meeting time data from LeopardWeb, which is more complex
    # and may be better handled by triggering a full course reprocess for changed courses.
  end

end
