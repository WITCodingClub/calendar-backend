# frozen_string_literal: true

class CourseReprocessService < ApplicationService
  attr_reader :courses, :user, :term_uid

  def initialize(courses, user)
    @courses = courses
    @user = user
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

    Rails.logger.info("[CourseReprocess] Starting for user #{user.id} (#{user.email}), term #{term.uid}")

    current_enrollments = user.enrollments.includes(:course).where(term: term)
    current_crns        = current_enrollments.map { |e| e.course.crn }

    @courses = courses.map { |c| c.deep_symbolize_keys }
    new_crns = @courses.map { |c| c[:crn].to_i }

    crns_to_remove = current_crns - new_crns

    Rails.logger.info("[CourseReprocess] User #{user.id}: CRNs to remove: #{crns_to_remove.inspect}")
    Rails.logger.info("[CourseReprocess] User #{user.id}: New CRNs: #{new_crns.inspect}")

    enrollments_to_remove = current_enrollments.select { |e| crns_to_remove.include?(e.course.crn) }
    removed_courses = []

    enrollments_to_remove.each do |enrollment|
      course = enrollment.course
      removed_courses << { crn: course.crn, title: course.title, course_number: course.course_number }

      events_deleted = cleanup_calendar_events_for_enrollment(enrollment)
      Rails.logger.info("[CourseReprocess] User #{user.id}: Deleted #{events_deleted} calendar events for CRN #{course.crn}")

      enrollment.destroy!
    end

    processed_courses = CourseProcessorService.new(courses, user).call

    Rails.logger.info("[CourseReprocess] User #{user.id}: Done — removed #{removed_courses.count} enrollments")

    user.update(calendar_needs_sync: true)

    {
      removed_enrollments: removed_courses.count,
      removed_courses:     removed_courses,
      processed_courses:   processed_courses
    }
  end

  private

  def validate_input!
    raise ArgumentError, "courses cannot be nil"   if courses.nil?
    raise ArgumentError, "courses must be an array" unless courses.is_a?(Array)
    raise ArgumentError, "courses cannot be empty"  if courses.empty?

    term_uids = courses.map { |c| c[:term] || c["term"] }.uniq
    raise ArgumentError, "All courses must be from the same term" if term_uids.length > 1
  end

  def cleanup_calendar_events_for_enrollment(enrollment)
    google_calendar = user.google_credential&.google_calendar
    return 0 unless google_calendar

    course           = enrollment.course
    meeting_time_ids = course.meeting_times.pluck(:id)
    return 0 if meeting_time_ids.empty?

    calendar_events = google_calendar.google_calendar_events.where(meeting_time_id: meeting_time_ids)
    return 0 if calendar_events.empty?

    service       = build_google_service
    deleted_count = 0

    calendar_events.find_each do |cal_event|
      begin
        service&.delete_event(google_calendar.google_calendar_id, cal_event.google_event_id)
      rescue Google::Apis::ClientError => e
        Rails.logger.warn("[CourseReprocess] User #{user.id}: Could not delete event #{cal_event.google_event_id}: #{e.message}")
      end
      cal_event.destroy!
      deleted_count += 1
    end

    deleted_count
  end

  def build_google_service
    return nil unless user.google_credential

    require "googleauth"
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         [ "https://www.googleapis.com/auth/calendar" ],
      access_token:  user.google_access_token,
      refresh_token: user.google_refresh_token,
      expires_at:    user.google_token_expires_at
    )

    if user.google_token_expired?
      credentials.refresh!
      user.google_credential.update!(
        access_token:     credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
    end

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = credentials
    service
  end
end
