# frozen_string_literal: true

class CourseDataSyncJob < ApplicationJob
  include ApplicationHelper

  queue_as :low

  limits_concurrency to: 1, key: -> { "course_data_sync" }

  def perform(term_uids: nil)
    term_uids ||= Term.active_uids.uniq

    return if term_uids.empty?

    Rails.logger.info "[CourseDataSyncJob] Starting sync for terms: #{term_uids}"

    term_uids.each { |uid| sync_term_courses(uid) }

    Rails.logger.info "[CourseDataSyncJob] Completed sync for #{term_uids.length} terms"
  end

  private

  def sync_term_courses(term_uid)
    term = Term.find_by(uid: term_uid)
    unless term
      Rails.logger.warn "[CourseDataSyncJob] Term not found for UID #{term_uid}"
      return
    end

    Rails.logger.info "[CourseDataSyncJob] Syncing courses for term #{term.name} (#{term_uid})"

    synced_count = 0
    error_count  = 0

    term.courses.includes(:meeting_times, meeting_times: { rooms: :building }).find_each(batch_size: 50) do |course|
      if sync_course_data(course, term_uid)
        synced_count += 1
      end
      sleep 0.1
    rescue => e
      error_count += 1
      Rails.logger.error "[CourseDataSyncJob] Failed to sync course #{course.crn}: #{e.message}"
    end

    Rails.logger.info "[CourseDataSyncJob] Term #{term.name} complete — #{synced_count} synced, #{error_count} errors"
  end

  def sync_course_data(course, term_uid)
    fresh_data = fetch_fresh_course_data(course.crn, term_uid)
    return false unless fresh_data

    if course_data_changed?(course, fresh_data) || meeting_times_need_update?(course)
      update_course_from_fresh_data(course, fresh_data)
      Rails.logger.info "[CourseDataSyncJob] Updated course #{course.crn}"
      return true
    end

    update_enrollment_counts(course, fresh_data)
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

  def meeting_times_need_update?(course)
    course.meeting_times.any? do |mt|
      mt.room&.number.to_i.zero? || mt.room&.building&.abbreviation == "TBD"
    end
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
