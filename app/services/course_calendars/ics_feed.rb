# frozen_string_literal: true

require "icalendar"

module CourseCalendars
  # Builds the iCalendar feed that calendar apps poll at /calendar/:token.
  #
  # EventBuilder gives the class, final exam, and university events with the
  # person's preferences applied, the same CourseCalendars::Event values the
  # Google and Outlook sync sends. This class only renders them, then adds the
  # friend meetings that the person sent to the feed. The body has no
  # per-request timestamps (DTSTAMP is the last change of each event), so the
  # same data gives the same bytes.
  #
  #   CourseCalendars::IcsFeed.new(user).to_ical
  class IcsFeed
    TZID = SchoolTimeZone::NAME

    # How often a calendar app should fetch the feed again, as an iCalendar
    # duration. Apps that subscribe by URL, such as Cozi, Apple Calendar, and
    # Outlook, read these properties in the body. Most ignore HTTP headers.
    # Google Calendar ignores both and uses its own schedule.
    REFRESH_INTERVAL = "PT1H"

    UID_DOMAIN = "calendar-util.wit.edu"

    # The rendered feed, from Rails.cache when no row that it reads has
    # changed (CacheKey). A miss builds it and keeps it for CacheKey::TTL.
    def self.cached_ical(user)
      Rails.cache.fetch(CacheKey.new(user).to_s, expires_in: CacheKey::TTL) { new(user).to_ical }
    end

    def initialize(user)
      @user    = user
      @courses = EventBuilder.courses_of(user)
    end

    def to_ical
      calendar.to_ical
    end

    def calendar
      builder = EventBuilder.new(@user)

      cal = Icalendar::Calendar.new
      cal.prodid = "-//WITCC//Course Calendar//EN"
      cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
      cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.full_name}")
      cal.refresh_interval = REFRESH_INTERVAL # RFC 7986
      cal.append_custom_property("X-PUBLISHED-TTL", REFRESH_INTERVAL) # Apple and Microsoft
      add_timezone(cal)

      events = builder.class_events(@courses) + builder.final_exam_events
      events += builder.university_events(time_scope: university_event_dates) if university_event_dates
      events.each { |event| cal.event { |e| fill(e, event) } }
      FriendMeetingEvents.new(@user).append_to(cal)

      cal
    end

    # An all-day event ends on the day after its last day (RFC 5545).
    def self.set_times(e, event)
      if event.all_day?
        e.dtstart = Icalendar::Values::Date.new(event.start_time.in_time_zone(TZID).to_date)
        e.dtend   = Icalendar::Values::Date.new(event.exclusive_end_date)
      else
        e.dtstart = time_value(event.start_time)
        e.dtend   = time_value(event.end_time)
      end
    end

    # RFC 5545 3.8.7.2: without a METHOD property, DTSTAMP is the time the
    # event last changed. Time.current would change the body (and the ETag)
    # on every request.
    def self.set_changed_at(e, changed_at)
      e.dtstamp       = time_value(changed_at)
      e.last_modified = time_value(changed_at)
      e.sequence      = changed_at.to_i / 60
    end

    def self.time_value(time) = Icalendar::Values::DateTime.new(time.in_time_zone(TZID), tzid: TZID)

    def self.uid(name) = "#{name}@#{UID_DOMAIN}"

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

    def fill(e, event)
      self.class.set_times(e, event)
      e.summary     = event.summary
      e.description = event.description unless event.description.to_s.empty?
      e.location    = event.location if event.location.present?
      if (recurrence = event.recurrence)
        e.rrule = recurrence.ical_rule(all_day: event.all_day?)
        recurrence.exdates.each do |time|
          e.append_exdate(event.all_day? ? Icalendar::Values::Date.new(time.to_date) : self.class.time_value(time))
        end
      end
      e.uid = self.class.uid(uid_name(event.source))
      fill_source(e, event.source)
      set_color(e, event.color_id)
      self.class.set_changed_at(e, event.changed_at)
      mark_free(e) if event.source.is_a?(UniversityCalendarEvent) && event.source.category == UniversityCalendarEvent::HOLIDAY
    end

    def uid_name(source)
      case source
      when Course::MeetingTime then "course-#{source.course.crn}-meeting-#{source.id}"
      when FinalExam           then "final-exam-#{source.id}"
      else                          "university-#{source.ics_uid}"
      end
    end

    def fill_source(e, source)
      e.categories = [ source.category.titleize ] if source.is_a?(UniversityCalendarEvent) && source.category.present?
    end

    def mark_free(e)
      e.append_custom_property("X-MICROSOFT-CDO-ALLDAYEVENT", "TRUE")
      e.append_custom_property("X-MICROSOFT-CDO-BUSYSTATUS", "FREE")
      e.transp = "TRANSPARENT"
    end

    def set_color(e, color_hex)
      return unless color_hex

      e.color = color_hex
      e.append_custom_property("X-APPLE-CALENDAR-COLOR", color_hex)
    end

    # The dates of the person's terms, for the university events. A term with
    # no start or end date yet falls back to the dates of the meeting times.
    def university_event_dates
      return @university_event_dates if defined?(@university_event_dates)

      @university_event_dates = term_dates
    end

    def term_dates
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
