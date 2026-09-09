# frozen_string_literal: true

class CourseDataSyncJob < ApplicationJob
  include ApplicationHelper

  queue_as :low

  # SolidQueue calls this key with the job's arguments, so it has to accept them.
  # A bare -> {} raises ArgumentError on any enqueue that passes term_uids.
  limits_concurrency to: 1, key: ->(*) { "course_data_sync" }

  def perform(term_uids: nil)
    term_uids ||= default_term_uids

    return if term_uids.empty?

    Rails.logger.info "[CourseDataSyncJob] Starting sync for terms: #{term_uids}"

    term_uids.each { |uid| sync_term_courses(uid) }

    Rails.logger.info "[CourseDataSyncJob] Completed sync for #{term_uids.length} terms"
  end

  private

  # Rooms and times only move for a term that is running or has not started yet.
  # Term.active_uids asks Banner, which lists every term back to 2014. That is
  # about 39,500 courses and 118,000 Banner requests a night, nearly all of them
  # for terms that ended years ago.
  def default_term_uids
    (Term.active.pluck(:uid) + Term.current_and_future.pluck(:uid)).uniq
  end

  def sync_term_courses(term_uid)
    term = Term.find_by(uid: term_uid)
    unless term
      Rails.logger.warn "[CourseDataSyncJob] Term not found for UID #{term_uid}"
      return
    end

    Rails.logger.info "[CourseDataSyncJob] Syncing courses for term #{term.name} (#{term_uid})"

    synced_count = 0
    error_count  = 0

    MeetingTimeChangeTrackable.with_enrollment_cache do
      term.courses.includes(:meeting_times, meeting_times: { rooms: :building }).find_each(batch_size: 50) do |course|
        if sync_course_data(course, term_uid)
          synced_count += 1
        end
        sleep 0.1
      rescue => e
        error_count += 1
        Rails.logger.error "[CourseDataSyncJob] Failed to sync course #{course.crn}: #{e.message}"
      end
    end

    Rails.logger.info "[CourseDataSyncJob] Term #{term.name} complete — #{synced_count} synced, #{error_count} errors"
  end

  def sync_course_data(course, term_uid)
    fresh_data = fetch_fresh_course_data(course.crn, term_uid)
    return false unless fresh_data

    course_changed = if course_data_changed?(course, fresh_data)
                       update_course_from_fresh_data(course, fresh_data)
                       true
    else
                       update_enrollment_counts(course, fresh_data)
    end

    meeting_times_changed = sync_meeting_times(course, fresh_data)
    faculty_changed       = sync_faculty(course, fresh_data)

    changed = course_changed || meeting_times_changed || faculty_changed
    Rails.logger.info "[CourseDataSyncJob] Updated course #{course.crn}" if changed

    changed
  end

  # The registrar reassigns sections after the term starts, and the extension
  # only posts a schedule when the student's course list changes. Without this
  # the calendar keeps naming the instructor who taught the section on the day
  # it was first imported.
  def sync_faculty(course, fresh_data)
    FacultyIngestService.call(course: course, raw_faculty: fresh_data[:faculty])
  end

  # The registrar moves sections between rooms after registration opens, and the
  # extension only posts a schedule when the student's course list changes. So
  # this job is the only thing that notices a room or time change, and it has to
  # write the new meeting times itself.
  def sync_meeting_times(course, fresh_data)
    raw = fresh_data[:meeting_times]
    # An empty payload means Banner told us nothing, not that the section stopped
    # meeting. Pruning on it would delete every meeting time and strand the
    # Google Calendar events that point at them.
    return false if raw.blank?

    before = meeting_times_fingerprint(course)

    touched_ids = MeetingTimesIngestService.call(
      course: course,
      raw_meeting_times: MeetingTimesIngestService.normalize_leopard_web(raw)
    )
    return false if touched_ids.empty?

    course.meeting_times.where.not(id: touched_ids).destroy_all
    course.meeting_times.reset

    before != meeting_times_fingerprint(course)
  end

  def meeting_times_fingerprint(course)
    course.meeting_times.includes(rooms: :building).map { |mt|
      [
        mt.day_of_week,
        mt.begin_time,
        mt.end_time,
        mt.start_date,
        mt.end_date,
        mt.rooms.map { |r| [ r.building.abbreviation, r.number ] }.sort
      ]
    }.sort_by(&:to_s)
  end

  def fetch_fresh_course_data(crn, term_uid)
    LeopardWebService.get_class_details(term: term_uid, course_reference_number: crn)
  rescue => e
    Rails.logger.error "[CourseDataSyncJob] Failed to fetch data for CRN #{crn}: #{e.message}"
    nil
  end

  def course_data_changed?(course, fresh_data)
    fresh_title           = fresh_data[:title].present? ? titleize_with_roman_numerals(fresh_data[:title].strip) : nil
    fresh_credit_hours    = fresh_data[:credit_hours]
    fresh_grade_mode      = fresh_data[:grade_mode]&.strip
    fresh_subject         = fresh_data[:subject]&.strip
    fresh_section_number  = normalize_section_number(fresh_data[:section_number])
    fresh_schedule_type   = extract_schedule_type(fresh_data[:schedule_type])

    [
      course.title          != fresh_title,
      course.credit_hours   != fresh_credit_hours,
      course.grade_mode     != fresh_grade_mode,
      course.subject        != fresh_subject,
      course.section_number != fresh_section_number,
      fresh_schedule_type && course.schedule_type != fresh_schedule_type
    ].any?
  end

  def update_course_from_fresh_data(course, fresh_data)
    attrs = {}
    attrs[:title]          = titleize_with_roman_numerals(fresh_data[:title].strip) if fresh_data[:title].present?
    attrs[:credit_hours]   = fresh_data[:credit_hours]   if fresh_data[:credit_hours]
    attrs[:grade_mode]     = fresh_data[:grade_mode]&.strip if fresh_data[:grade_mode]
    attrs[:subject]        = fresh_data[:subject]&.strip    if fresh_data[:subject]
    attrs[:section_number] = normalize_section_number(fresh_data[:section_number]) if fresh_data[:section_number]

    schedule_type = extract_schedule_type(fresh_data[:schedule_type])
    attrs[:schedule_type] = schedule_type if schedule_type

    attrs[:seats_available] = fresh_data[:seats_available] unless fresh_data[:seats_available].nil?
    attrs[:seats_capacity]  = fresh_data[:seats_capacity]  unless fresh_data[:seats_capacity].nil?

    course.update!(attrs) if attrs.any?
  end

  def update_enrollment_counts(course, fresh_data)
    attrs = {}
    attrs[:seats_available] = fresh_data[:seats_available] unless fresh_data[:seats_available].nil?
    attrs[:seats_capacity]  = fresh_data[:seats_capacity]  unless fresh_data[:seats_capacity].nil?

    course.update!(attrs) if attrs.any?
    attrs.any?
  end

  def extract_schedule_type(raw)
    return nil if raw.blank?

    match = raw.to_s.match(/\(([^)]+)\)/)
    match ? match[1].strip : raw.strip
  end
end
