# frozen_string_literal: true

# Service to reprocess a user's courses for a term
# Compares the new course list with existing enrollments and:
# 1. Removes enrollments no longer in the new course list
# 2. Processes new/updated courses via CourseProcessorService
# 3. Cleans up orphaned calendar events
# 4. Triggers calendar sync to update Google Calendar
class CourseReprocessService < ApplicationService
  attr_reader :courses, :user, :term_uid

  def initialize(courses, user)
    @courses = courses
    @user = user
    # Extract term UID from first course (all courses should be same term)
    if courses.is_a?(Array) && courses.any?
      first_course = courses.first
      @term_uid = first_course.is_a?(Hash) ? (first_course[:term] || first_course["term"]) : nil
    end
    super()
  end

  def call
    validate_input!

    term = Term.find_by(uid: term_uid)
    raise ArgumentError, "Term with UID #{term_uid} not found" unless term

    Rails.logger.info("[CourseReprocess] Starting reprocess for user #{user.id} (#{user.email}), term #{term.uid} (#{term.name})")

    # Get current enrollments for this user and term
    current_enrollments = user.enrollments.includes(:course).where(term: term)
    current_crns = current_enrollments.map { |e| e.course.crn }

    # Get new CRNs from the incoming course list
    # Convert courses to use symbol keys for CourseProcessorService
    @courses = courses.map { |c| c.deep_symbolize_keys }
    new_crns = @courses.map { |c| c[:crn].to_i }

    Rails.logger.info("[CourseReprocess] User #{user.id}: Current CRNs: #{current_crns.inspect}")
    Rails.logger.info("[CourseReprocess] User #{user.id}: New CRNs: #{new_crns.inspect}")

    # Find enrollments to remove (CRNs no longer in the new list)
    crns_to_remove = current_crns - new_crns
    crns_to_add = new_crns - current_crns
    crns_unchanged = current_crns & new_crns

    Rails.logger.info("[CourseReprocess] User #{user.id}: CRNs to remove: #{crns_to_remove.inspect}")
    Rails.logger.info("[CourseReprocess] User #{user.id}: CRNs to add: #{crns_to_add.inspect}")
    Rails.logger.info("[CourseReprocess] User #{user.id}: CRNs unchanged: #{crns_unchanged.inspect}")

    enrollments_to_remove = current_enrollments.select { |e| crns_to_remove.include?(e.course.crn) }
    removed_courses = []

    enrollments_to_remove.each do |enrollment|
      course = enrollment.course
      removed_courses << {
        crn: course.crn,
        title: course.title,
        course_number: course.course_number
      }

      Rails.logger.info("[CourseReprocess] User #{user.id}: Removing enrollment for course CRN #{course.crn} (#{course.title})")

      # Delete associated calendar events before removing enrollment
      events_deleted = cleanup_calendar_events_for_enrollment(enrollment)
      Rails.logger.info("[CourseReprocess] User #{user.id}: Deleted #{events_deleted} calendar events for CRN #{course.crn}")

      # Destroy the enrollment (course remains in DB for other users)
      enrollment.destroy!
    end

    # Process new courses (adds new enrollments, updates existing)
    # Note: CourseProcessorService will trigger GoogleCalendarSyncJob at the end
    processed_courses = CourseProcessorService.new(courses, user).call

    Rails.logger.info("[CourseReprocess] User #{user.id}: Completed - removed #{removed_courses.count} enrollments, processed #{processed_courses.count} courses")

    # Mark calendar as needing sync (will be picked up by nightly job if immediate sync fails)
    user.update(calendar_needs_sync: true)

    {
      removed_enrollments: removed_courses.count,
      removed_courses: removed_courses,
      processed_courses: processed_courses
    }
  end

  private

  def user_calendar_service
    @user_calendar_service ||= begin
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = build_google_authorization
      service
    end
  end

  def build_google_authorization
    require "googleauth"
    return unless user.google_credential

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: user.google_access_token,
      refresh_token: user.google_refresh_token,
      expires_at: user.google_token_expires_at
    )

    # Refresh the token if needed
    if user.google_token_expired?
      credentials.refresh!
      user.google_credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
    end

    credentials
  end

  def validate_input!
    raise ArgumentError, "courses cannot be nil" if courses.nil?
    raise ArgumentError, "courses must be an array" unless courses.is_a?(Array)
    raise ArgumentError, "courses cannot be empty" if courses.empty?

    # Ensure all courses have the same term
    term_uids = courses.map { |c| c[:term] || c["term"] }.uniq
    raise ArgumentError, "All courses must be from the same term" if term_uids.length > 1
  end

  def cleanup_calendar_events_for_enrollment(enrollment)
    return 0 if user.google_course_calendar_id.blank?

    course = enrollment.course
    meeting_time_ids = course.meeting_times.pluck(:id)
    return 0 if meeting_time_ids.empty?

    # Find and delete calendar events for these meeting times
    google_calendar = user.google_calendars.find_by(google_calendar_id: user.google_course_calendar_id)
    return 0 unless google_calendar

    calendar_events = google_calendar.google_calendar_events.where(meeting_time_id: meeting_time_ids)
    return 0 if calendar_events.empty?

    # Delete events from Google Calendar and database
    deleted_count = 0
    service = user_calendar_service

    calendar_events.find_each do |cal_event|
      begin
        Rails.logger.info("[CourseReprocess] User #{user.id}: Deleting calendar event #{cal_event.google_event_id} for meeting_time #{cal_event.meeting_time_id}")
        service.delete_event(user.google_course_calendar_id, cal_event.google_event_id)
        cal_event.destroy!
        deleted_count += 1
      rescue Google::Apis::ClientError => e
        # Event may already be deleted in Google Calendar, just remove from DB
        Rails.logger.warn("[CourseReprocess] User #{user.id}: Failed to delete calendar event #{cal_event.google_event_id}: #{e.message}")
        cal_event.destroy!
        deleted_count += 1
      end
    end

    deleted_count
  end

end
