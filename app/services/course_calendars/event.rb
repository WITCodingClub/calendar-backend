# frozen_string_literal: true

module CourseCalendars
  # One event of a person's calendar, as every destination gets it: the
  # Google and Outlook sync, and the ICS feed. EventBuilder makes it once from
  # its source record (a Course::MeetingTime, a FinalExam, or a
  # UniversityCalendarEvent) with the person's preferences applied.
  # FriendMeeting#calendar_event makes one for a friend meeting.
  #
  # end_time of an all-day event is a time on its last day. exclusive_end_date
  # is the day after, the end that iCalendar, Google, and Outlook take.
  #
  # changed_at is the last change to anything the event shows, for the ICS
  # feed's LAST-MODIFIED.
  class Event < Data.define(:source, :summary, :description, :location, :start_time, :end_time, :all_day,
                            :recurrence, :reminder_settings, :color_id, :visibility, :changed_at)
    # The last change to how the app builds an event from the same rows. No
    # row's updated_at moves for such a change, so changed_at is at least this
    # time, and calendar apps fetch the new copy of the feed. Move it forward
    # when a code change alters an event body.
    LOGIC_CHANGED_AT = SchoolTimeZone.zone.local(2026, 11, 16, 15, 0)

    # The records that each kind of event shows besides its source, as
    # association paths from the source. EventBuilder::COURSE_INCLUDES and
    # its other includes load them, changed_at reads their updated_at, and
    # IcsFeed::CacheKey fingerprints their tables (its spec checks this list).
    READS = {
      "Course::MeetingTime"     => [ :meeting_time_rooms, { rooms: :building }, { course: :faculties } ],
      "FinalExam"               => [ :term, { course: :faculties } ],
      "UniversityCalendarEvent" => [ :term ]
    }.freeze

    # The latest updated_at of the source and the records it READS.
    def self.read_at(source)
      records_read(source, READS.fetch(source.class.name)).push(source).filter_map(&:updated_at).max
    end

    def self.records_read(record, paths)
      Array(paths).flat_map do |path|
        nested = path.is_a?(Hash) ? path : { path => [] }
        nested.flat_map do |name, inner|
          Array(record.public_send(name)).compact.flat_map { |read| [ read, *records_read(read, inner) ] }
        end
      end
    end
    private_class_method :records_read

    # The fields that each destination sends, so a sync without force sees
    # each change. The description is last: rows saved before it was in the
    # hash differ once and update on their next sync.
    def self.hash_of(fields)
      Digest::SHA256.hexdigest([
        fields[:summary],
        fields[:location],
        fields[:start_time]&.to_i,
        fields[:end_time]&.to_i,
        fields[:recurrence]&.to_json,
        fields[:reminder_settings]&.to_json,
        fields[:color_id]&.to_s,
        fields[:visibility],
        fields[:all_day],
        fields[:description]
      ].join("|"))
    end

    def initialize(source:, summary:, start_time:, end_time:, description: nil, location: nil, all_day: nil,
                   recurrence: nil, reminder_settings: nil, color_id: nil, visibility: nil, changed_at: nil)
      super
    end

    def all_day? = all_day ? true : false

    def exclusive_end_date
      end_time.in_time_zone(SchoolTimeZone::NAME).to_date + 1.day
    end

    def excluded_dates = recurrence ? recurrence.excluded_dates : []

    # The calendar_events column that tracks the source, and the source id.
    def source_key = [ CalendarEvent.source_column(source), source.id ]

    # The fields as a calendar_events row keeps them.
    def fields
      {
        summary: summary, description: description, location: location, start_time: start_time,
        end_time: end_time, all_day: all_day, recurrence: recurrence&.lines,
        reminder_settings: reminder_settings, color_id: color_id, visibility: visibility
      }
    end

    def data_hash = self.class.hash_of(fields)
  end
end
