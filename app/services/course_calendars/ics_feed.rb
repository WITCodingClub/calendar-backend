# frozen_string_literal: true

require "icalendar"

module CourseCalendars
  # Builds the iCalendar feed that calendar apps poll at /calendar/:token.
  #
  # EventBuilder gives the class, final exam, and university events with the
  # person's preferences applied, as the Google and Outlook sync gets them.
  # This class only renders them, then adds the friend meetings that the
  # person sent to the feed. The body has no per-request timestamps (DTSTAMP
  # is the last change of each event), so the same data gives the same bytes.
  #
  #   CourseCalendars::IcsFeed.new(user).to_ical
  class IcsFeed
    TZID = SchoolTimeZone::NAME

    # How often a calendar app should fetch the feed again, as an iCalendar
    # duration. Apps that subscribe by URL, such as Cozi, Apple Calendar, and
    # Outlook, read these properties in the body. Most ignore HTTP headers.
    # Google Calendar ignores both and uses its own schedule.
    REFRESH_INTERVAL = "PT1H"

    # The last change to how the feed builds an event from the same rows. No
    # row's updated_at moves for such a change, so LAST-MODIFIED and SEQUENCE
    # are at least this time, and calendar apps fetch the new copy. Move it
    # forward when a code change alters an event body.
    EVENT_LOGIC_CHANGED_AT = Time.find_zone!(TZID).local(2026, 11, 16, 12, 0)

    UID_DOMAIN = "calendar-util.wit.edu"

    # The rendered feed, from Rails.cache when no row that it reads has
    # changed (CacheKey). A miss builds it and keeps it for CacheKey::TTL.
    def self.cached_ical(user)
      Rails.cache.fetch(CacheKey.new(user).to_s, expires_in: CacheKey::TTL) { new(user).to_ical }
    end

    def initialize(user)
      @user    = user
      @courses = user.courses
                     .includes(:term, meeting_times: [ :meeting_time_rooms, { rooms: :building }, { course: [ :faculties, :term ] } ])
                     .to_a
    end

    def to_ical
      calendar.to_ical
    end

    def calendar
      @preference_resolver = Preferences::Resolver.new(@user)
      @recurrence          = RecurrenceBuilder.preloaded(@user, @courses)
      preferences = Preferences::Applier.new(@user, resolver: @preference_resolver)
      builder     = EventBuilder.new(@user, recurrence: @recurrence, preferences: preferences)

      cal = Icalendar::Calendar.new
      cal.prodid = "-//WITCC//Course Calendar//EN"
      cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
      cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.full_name}")
      cal.refresh_interval = REFRESH_INTERVAL # RFC 7986
      cal.append_custom_property("X-PUBLISHED-TTL", REFRESH_INTERVAL) # Apple and Microsoft
      add_timezone(cal)

      builder.class_entries(@courses).each { |entry| cal.event { |e| fill_class_event(e, entry.source, entry.event) } }
      builder.final_exam_entries.each { |entry| cal.event { |e| fill_final_exam(e, entry.source, entry.event) } }
      if (dates = university_event_dates)
        builder.university_event_entries(time_scope: dates).each do |entry|
          cal.event { |e| fill_university_event(e, entry.source, entry.event) }
        end
      end
      FriendMeetingEvents.new(@user).append_to(cal)

      cal
    end

    private

    def add_timezone(cal)
      cal.timezone do |t|
        t.tzid = TZID
        t.daylight do |d|
          d.tzoffsetfrom = "-0500"
          d.tzoffsetto   = "-0400"
          d.tzname       = "EDT"
          d.dtstart      = "19700308T020000"
          d.rrule        = "FREQ=YEARLY;BYMONTH=3;BYDAY=2SU"
        end
        t.standard do |s|
          s.tzoffsetfrom = "-0400"
          s.tzoffsetto   = "-0500"
          s.tzname       = "EST"
          s.dtstart      = "19701101T020000"
          s.rrule        = "FREQ=YEARLY;BYMONTH=11;BYDAY=1SU"
        end
      end
    end

    # The class location is the catalog's room text. The feed has never
    # applied the location template to classes, while Google and Outlook do.
    def fill_class_event(e, meeting_time, event)
      set_times(e, event)
      set_text(e, event.merge(location: meeting_time.location_text))

      e.rrule = @recurrence.build_recurrence_rule(meeting_time, date_only_until: event[:all_day]).delete_prefix("RRULE:")
      @recurrence.holiday_dates(meeting_time).each do |date|
        e.append_exdate(event[:all_day] ? Icalendar::Values::Date.new(date) : time_value(@recurrence.exdate_time(date, event[:start_time])))
      end

      e.uid = "course-#{meeting_time.course.crn}-meeting-#{meeting_time.id}@#{UID_DOMAIN}"
      set_color(e, event[:color_id] || meeting_time.event_color)
      set_changed_at(e, class_changed_at(meeting_time))
    end

    def fill_final_exam(e, final_exam, event)
      set_times(e, event)
      set_text(e, event)
      e.uid = "final-exam-#{final_exam.id}@#{UID_DOMAIN}"
      set_color(e, event[:color_id])

      course = final_exam.course
      set_changed_at(e, [
        final_exam.updated_at,
        final_exam.term&.updated_at,
        course&.updated_at,
        *course&.faculties&.map(&:updated_at),
        @preference_resolver.last_changed_at_for(final_exam),
        EVENT_LOGIC_CHANGED_AT
      ].compact.max)
    end

    def fill_university_event(e, event_record, event)
      set_times(e, event)
      set_text(e, event)
      e.uid        = "university-#{event_record.ics_uid}@#{UID_DOMAIN}"
      e.categories = [ event_record.category.titleize ] if event_record.category.present?
      set_color(e, event[:color_id])
      set_changed_at(e, [
        event_record.updated_at,
        event_record.term&.updated_at,
        @preference_resolver.last_changed_at_for(event_record),
        EVENT_LOGIC_CHANGED_AT
      ].compact.max)

      return unless event_record.category == "holiday"

      e.append_custom_property("X-MICROSOFT-CDO-ALLDAYEVENT", "TRUE")
      e.append_custom_property("X-MICROSOFT-CDO-BUSYSTATUS", "FREE")
      e.transp = "TRANSPARENT"
    end

    # An all-day event ends on the day after its last day (RFC 5545).
    def set_times(e, event)
      if event[:all_day]
        e.dtstart = Icalendar::Values::Date.new(event[:start_time].to_date)
        e.dtend   = Icalendar::Values::Date.new(event[:end_time].to_date + 1.day)
      else
        e.dtstart = time_value(event[:start_time])
        e.dtend   = time_value(event[:end_time])
      end
    end

    def set_text(e, event)
      e.summary     = event[:summary]
      e.description = event[:description] unless event[:description].to_s.empty?
      e.location    = event[:location]    if event[:location].present?
    end

    def set_color(e, color_hex)
      return unless color_hex

      e.color = color_hex
      e.append_custom_property("X-APPLE-CALENDAR-COLOR", color_hex)
    end

    # RFC 5545 3.8.7.2: without a METHOD property, DTSTAMP is the time the
    # event last changed. Time.current would change the body (and the ETag)
    # on every request.
    def set_changed_at(e, changed_at)
      e.dtstamp       = time_value(changed_at)
      e.last_modified = time_value(changed_at)
      e.sequence      = changed_at.to_i / 60
    end

    def time_value(time) = Icalendar::Values::DateTime.new(time, tzid: TZID)

    # The last change to anything that the class event shows. A calendar client
    # keeps its copy until LAST-MODIFIED or SEQUENCE goes up, so a new title
    # template, color, holiday, or room must move it too. Every row here is
    # already loaded, so this runs no query.
    def class_changed_at(meeting_time)
      [
        meeting_time.course.updated_at,
        meeting_time.updated_at,
        @preference_resolver.last_changed_at_for(meeting_time),
        *meeting_time.course.faculties.map(&:updated_at),
        *meeting_time.meeting_time_rooms.map(&:updated_at),
        *meeting_time.rooms.map(&:updated_at),
        *meeting_time.rooms.filter_map { |room| room.building&.updated_at },
        *@recurrence.holidays_for_meeting_time(meeting_time).map(&:updated_at),
        EVENT_LOGIC_CHANGED_AT
      ].compact.max
    end

    # The dates of the person's terms, for the university events. A term with
    # no start or end date yet falls back to the dates of the meeting times.
    def university_event_dates
      term_ids = @courses.map(&:term_id).compact.uniq
      return if term_ids.empty?

      min, max = Term.where(id: term_ids).where.not(start_date: nil).where.not(end_date: nil)
                     .pick(Arel.sql("min(start_date)"), Arel.sql("max(end_date)"))
      unless min && max
        meeting_times = @courses.flat_map(&:meeting_times)
        min = meeting_times.filter_map(&:start_date).min
        max = meeting_times.filter_map(&:end_date).max
      end
      min..max if min && max
    end
  end
end
