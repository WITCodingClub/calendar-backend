# frozen_string_literal: true

module Catalog
  # Brings stored sections up to date from Banner: the title and other
  # details, the seats, the meeting times and rooms, the instructors, and the
  # lecture and lab pairs. It records the time in courses.banner_synced_at, so
  # Courses::Processor can skip Banner for a section that is current.
  #
  # Catalog::CourseDataSyncJob calls it for every section of the active terms
  # each night, and Catalog::SectionRefreshJob for the sections of one schedule.
  class SectionSync
    BATCH_SIZE = 50

    # The enrollment flags and the calendar marks of the change trackers
    # (CourseCalendars::SyncMarker) are loaded and sent once for each batch,
    # and every section shares one Locations. Syncs the courses in the order
    # of the ids. A CooldownError stops the run; any other error is reported,
    # and the next section syncs. Returns { synced:, errors: }.
    def self.call_many(course_ids)
      sync = new
      counts = { synced: 0, errors: 0 }

      course_ids.each_slice(BATCH_SIZE) do |slice|
        courses = Course.where(id: slice).includes(:term, meeting_times: [ :meeting_time_rooms, { rooms: :building } ])
                        .index_by(&:id).values_at(*slice).compact
        flags = CourseCalendars::SyncMarker.enrollment_flags(courses.map(&:id))
        CourseCalendars::SyncMarker.batch_with_enrollment_flags(flags) do
          courses.each do |course|
            changed = BannerThrottle.report_unless_cooldown(fallback: :error, course_id: course.id, crn: course.crn) do
              sync.call(course, course.term.uid)
            end
            counts[:errors] += 1 if changed == :error
            counts[:synced] += 1 if changed == true
          end
        end
      end

      counts
    end

    # Sections share buildings and rooms, so callers pass one Locations for a
    # whole run.
    def initialize(locations: Catalog::MeetingTimesIngest::Locations.new)
      @locations = locations
    end

    # Returns true when Banner changed the section, false when nothing changed
    # or Banner returned nothing.
    def call(course, term_uid)
      details = BannerThrottle.report_unless_cooldown(crn: course.crn, term_uid: term_uid) do
        Catalog::LeopardWebClient.get_class_details(term: term_uid, course_reference_number: course.crn)
      end
      return false unless details

      section = BannerSection.from_class_details(details)
      course_changed        = sync_section(course, section, term_uid)
      meeting_times_changed = sync_meeting_times(course, section)
      # The registrar reassigns sections after the term starts, and the
      # extension only posts a schedule when the student's course list
      # changes. Without this the calendar keeps naming the instructor who
      # taught the section on the day it was first imported.
      faculty_changed = Faculties::Ingest.call(course: course, raw_faculty: section.faculty)
      # The registrar can change which lab goes with which lecture.
      Catalog::SectionLinksSync.call(course) if course.is_section_linked

      changed = course_changed || meeting_times_changed || faculty_changed
      # A timestamp, not a change to the section, so no calendar resync.
      course.update_column(:banner_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info "[Catalog::SectionSync] Updated course #{course.crn}" if changed

      changed
    end

    private

    # A value Banner did not send keeps the stored one. An unknown schedule
    # type also keeps the stored one.
    def sync_section(course, section, term_uid)
      attrs = section.attributes.merge(section.counts)
      attrs[:subject] = Catalog::SubjectLabels.for_term(attrs[:subject], term_uid, stored: course.subject) if attrs[:subject]
      attrs[:schedule_type] = section.schedule_type if section.schedule_type

      course.assign_attributes(attrs)
      return false unless course.changed?

      course.save!
      true
    end

    # The registrar moves sections between rooms after registration opens, and the
    # extension only posts a schedule when the student's course list changes. So
    # the sync is the only thing that notices a room or time change, and it has to
    # write the new meeting times itself.
    def sync_meeting_times(course, section)
      # No meetings means Banner told us nothing, not that the section stopped
      # meeting. Pruning on it would delete every meeting time and strand the
      # calendar events that point at them.
      return false if section.meeting_times.empty?

      # The batch preloads meeting times with their rooms and buildings, so the
      # first fingerprint sends no query.
      before = meeting_times_fingerprint(course.meeting_times)

      touched_ids = Catalog::MeetingTimesIngest.call(
        course: course,
        meetings: section.meeting_times,
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
  end
end
