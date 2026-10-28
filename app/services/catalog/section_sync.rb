# frozen_string_literal: true

module Catalog
  # Brings one stored section up to date from Banner: the title and other
  # details, the seats, the meeting times and rooms, the instructors, and the
  # lecture and lab pairs. It records the time in courses.banner_synced_at, so
  # Courses::Processor can skip Banner for a section that is current.
  #
  # Catalog::CourseDataSyncJob calls it for every section of the active terms
  # each night, and Catalog::SectionRefreshJob for the sections of one schedule.
  class SectionSync
    include ApplicationHelper

    # Sections share buildings and rooms, so callers pass one Locations for a
    # whole run.
    def initialize(locations: Catalog::MeetingTimesIngest::Locations.new)
      @locations = locations
    end

    # Returns true when Banner changed the section, false when nothing changed
    # or Banner returned nothing.
    def call(course, term_uid)
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
      # The registrar can change which lab goes with which lecture.
      Catalog::SectionLinksSync.call(course) if course.is_section_linked

      changed = course_changed || meeting_times_changed || faculty_changed
      # A timestamp, not a change to the section, so no calendar resync.
      course.update_column(:banner_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info "[Catalog::SectionSync] Updated course #{course.crn}" if changed

      changed
    end

    private

    # The registrar reassigns sections after the term starts, and the extension
    # only posts a schedule when the student's course list changes. Without this
    # the calendar keeps naming the instructor who taught the section on the day
    # it was first imported.
    def sync_faculty(course, fresh_data)
      Faculties::Ingest.call(course: course, raw_faculty: fresh_data[:faculty])
    end

    # The registrar moves sections between rooms after registration opens, and the
    # extension only posts a schedule when the student's course list changes. So
    # the sync is the only thing that notices a room or time change, and it has to
    # write the new meeting times itself.
    def sync_meeting_times(course, fresh_data)
      raw = fresh_data[:meeting_times]
      # An empty payload means Banner told us nothing, not that the section stopped
      # meeting. Pruning on it would delete every meeting time and strand the
      # Google Calendar events that point at them.
      return false if raw.blank?

      # The batch preloads meeting times with their rooms and buildings, so the
      # first fingerprint sends no query.
      before = meeting_times_fingerprint(course.meeting_times)

      touched_ids = Catalog::MeetingTimesIngest.call(
        course: course,
        raw_meeting_times: Catalog::MeetingTimesIngest.normalize_leopard_web(raw),
        locations: @locations,
        existing_meeting_times: course.meeting_times.to_a
      )
      return false if touched_ids.empty?

      course.meeting_times.where.not(id: touched_ids).destroy_all
      course.meeting_times.reset

      before != meeting_times_fingerprint(course.meeting_times.includes(rooms: :building))
    end

    def meeting_times_fingerprint(meeting_times)
      meeting_times.map { |mt|
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
      Catalog::LeopardWebClient.get_class_details(term: term_uid, course_reference_number: crn)
    rescue Catalog::BannerThrottle::CooldownError
      raise
    rescue => e
      Rails.error.report(e, handled: true, context: { crn: crn, term_uid: term_uid })
      nil
    end

    def course_data_changed?(course, fresh_data)
      fresh_title           = fresh_data[:title].present? ? titleize_with_roman_numerals(fresh_data[:title].strip) : nil
      fresh_grade_mode      = fresh_data[:grade_mode]&.strip
      fresh_subject         = fresh_data[:subject]&.strip
      fresh_section_number  = normalize_section_number(fresh_data[:section_number])
      fresh_schedule_type   = extract_schedule_type(fresh_data[:schedule_type])

      [
        course.title          != fresh_title,
        course.grade_mode     != fresh_grade_mode,
        course.subject        != fresh_subject,
        course.section_number != fresh_section_number,
        fresh_schedule_type && course.schedule_type != fresh_schedule_type
      ].any?
    end

    # Credit hours are not taken from getClassDetails. Its "Credit Hours" is the
    # course's credits, so it gives a lab the lecture's 4. The import keeps the
    # section's own credits (Catalog::Importer.credit_hours_for), which are nil
    # for a lab. The catalog:repair_credit_hours task corrects rows this job overwrote.
    def update_course_from_fresh_data(course, fresh_data)
      attrs = {}
      attrs[:title]          = titleize_with_roman_numerals(fresh_data[:title].strip) if fresh_data[:title].present?
      attrs[:grade_mode]     = fresh_data[:grade_mode]&.strip if fresh_data[:grade_mode]
      attrs[:subject]        = fresh_data[:subject]&.strip    if fresh_data[:subject]
      attrs[:section_number] = normalize_section_number(fresh_data[:section_number]) if fresh_data[:section_number]

      schedule_type = extract_schedule_type(fresh_data[:schedule_type])
      attrs[:schedule_type] = schedule_type if schedule_type

      attrs[:seats_available] = fresh_data[:seats_available] unless fresh_data[:seats_available].nil?
      attrs[:seats_capacity]  = fresh_data[:seats_capacity]  unless fresh_data[:seats_capacity].nil?
      attrs.merge!(waitlist_counts(fresh_data))

      course.update!(attrs) if attrs.any?
    end

    def update_enrollment_counts(course, fresh_data)
      attrs = {}
      attrs[:seats_available] = fresh_data[:seats_available] unless fresh_data[:seats_available].nil?
      attrs[:seats_capacity]  = fresh_data[:seats_capacity]  unless fresh_data[:seats_capacity].nil?
      attrs.merge!(waitlist_counts(fresh_data))

      course.update!(attrs) if attrs.any?
      attrs.any?
    end

    # Both counts or neither, so a section never shows half of a waitlist.
    def waitlist_counts(fresh_data)
      return {} if fresh_data[:waitlist_capacity].nil? || fresh_data[:waitlist_available].nil?

      fresh_data.slice(:waitlist_capacity, :waitlist_available)
    end

    def extract_schedule_type(raw)
      return nil if raw.blank?

      match = raw.to_s.match(/\(([^)]+)\)/)
      match ? match[1].strip : raw.strip
    end
  end
end
