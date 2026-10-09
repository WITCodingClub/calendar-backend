# frozen_string_literal: true

require "icalendar"

module CourseCalendars
  # Builds the iCalendar feed that calendar apps poll at /calendar/:token.
  #
  # The feed has one recurring event for each class meeting, then the finals,
  # the university events, and the friend meetings that the user sent to it.
  # The body has no per-request timestamps (DTSTAMP is the last change of each
  # event), so the same data gives the same bytes.
  #
  #   CourseCalendars::IcsFeed.new(user).to_ical
  class IcsFeed
    include ApplicationHelper

    TZID = "America/New_York"

    # How often a calendar app should fetch the feed again, as an iCalendar
    # duration. Apps that subscribe by URL, such as Cozi, Apple Calendar, and
    # Outlook, read these properties in the body. Most ignore HTTP headers.
    # Google Calendar ignores both and uses its own schedule.
    REFRESH_INTERVAL = "PT1H"

    def initialize(user)
      @user    = user
      @courses = user.courses
                     .includes(:term, meeting_times: [ :meeting_time_rooms, { rooms: :building }, { course: [ :faculties, :term ] } ])
      # Loads the courses now: the finals relation needs their IDs.
      @final_exams = FinalExam.where(course_id: @courses.map(&:id))
                              .where(exam_date: Time.zone.today..)
                              .includes(:course)
    end

    def to_ical
      calendar.to_ical
    end

    def calendar
      @preference_resolver = Preferences::Resolver.new(@user)
      @template_renderer   = Preferences::TemplateRenderer.new
      @holidays            = Holidays.new(@courses)
      @recurrence_end      = RecurrenceEnd.new(@courses)

      cal = Icalendar::Calendar.new
      cal.prodid = "-//WITCC//Course Calendar//EN"
      cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
      cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.full_name}")
      cal.refresh_interval = REFRESH_INTERVAL # RFC 7986
      cal.append_custom_property("X-PUBLISHED-TTL", REFRESH_INTERVAL) # Apple and Microsoft
      add_timezone(cal)

      @courses.each do |course|
        meeting_times_without_duplicates(course).each do |meeting_time|
          next if meeting_time.day_of_week.blank?

          cal.event { |e| fill_class_event(e, course, meeting_time) }
        end
      end

      FinalExamEvents.new(@final_exams).append_to(cal)
      UniversityEvents.new(@user, @courses, @preference_resolver).append_to(cal)
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

    # Meeting times with the same day and hours are one event. Of each group,
    # the first one with a real room wins.
    def meeting_times_without_duplicates(course)
      course.meeting_times
            .group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
            .map do |_key, group|
              non_tbd = group.reject { |mt| LocationHelper.tbd_building?(mt.building) || mt.rooms.all? { |r| LocationHelper.tbd_room?(r) } }
              non_tbd.any? ? non_tbd.first : group.first
            end
    end

    def fill_class_event(e, course, meeting_time)
      first_meeting_date = find_first_meeting_date(meeting_time)
      return unless first_meeting_date

      start_time = parse_time(first_meeting_date, meeting_time.begin_time)
      end_time   = parse_time(first_meeting_date, meeting_time.end_time)

      if meeting_time.all_day?
        e.dtstart = Icalendar::Values::Date.new(first_meeting_date)
        e.dtend   = Icalendar::Values::Date.new(first_meeting_date + 1.day)
      else
        e.dtstart = Icalendar::Values::DateTime.new(start_time, tzid: TZID)
        e.dtend   = Icalendar::Values::DateTime.new(end_time,   tzid: TZID)
      end

      prefs   = @preference_resolver.resolve_for(meeting_time)
      context = Preferences::TemplateRenderer.build_context_from_meeting_time(meeting_time)

      e.summary = if prefs[:title_template].present?
                    @template_renderer.render(prefs[:title_template], context)
      else
                    titleize_with_roman_numerals(course.title)
      end

      e.description = @template_renderer.render(prefs[:description_template], context) if prefs[:description_template].present?

      location = class_location(meeting_time)
      e.location = location if location

      add_recurrence(e, meeting_time, course)

      @holidays.exdates_for(meeting_time, start_time).each do |exdate|
        if meeting_time.all_day?
          e.append_exdate(Icalendar::Values::Date.new(exdate.to_date))
        else
          e.append_exdate(Icalendar::Values::DateTime.new(exdate, tzid: TZID))
        end
      end

      e.uid = "course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu"

      color_hex = GoogleCalendar::Colors.normalize(prefs[:color_id]) || meeting_time.event_color
      e.color = color_hex
      e.append_custom_property("X-APPLE-CALENDAR-COLOR", color_hex)

      # RFC 5545 3.8.7.2: without a METHOD property, DTSTAMP is the time
      # the event last changed. Time.current would change the body (and
      # the ETag) on every request.
      last_modified = meeting_time_last_modified(course, meeting_time)
      e.dtstamp = Icalendar::Values::DateTime.new(last_modified, tzid: TZID)
      e.last_modified = Icalendar::Values::DateTime.new(last_modified, tzid: TZID)
      e.sequence      = (last_modified.to_i / 60)
    end

    def class_location(meeting_time)
      non_tbd_rooms = meeting_time.rooms.reject { |r| LocationHelper.tbd_room?(r) }
      if non_tbd_rooms.any? && meeting_time.building &&
         !LocationHelper.tbd_building?(meeting_time.building)
        "#{meeting_time.building.name} - #{non_tbd_rooms.map(&:formatted_number).join(' / ')}"
      elsif non_tbd_rooms.any?
        non_tbd_rooms.map(&:formatted_number).join(" / ")
      elsif LocationHelper.tbd_building?(meeting_time.building) || LocationHelper.tbd_room?(meeting_time.room)
        "TBD"
      end
    end

    def add_recurrence(e, meeting_time, course)
      recurrence_end = @recurrence_end.for(meeting_time, course)
      day_sym        = meeting_time.day_of_week.to_sym

      if meeting_time.all_day?
        until_time = Time.utc(recurrence_end.year, recurrence_end.month, recurrence_end.day)
        rule       = IceCube::Rule.weekly.day(day_sym).until(until_time)
        e.rrule    = rule.to_ical.gsub(/UNTIL=(\d{8})T\d{6}Z?/, 'UNTIL=\1')
      else
        # End-of-day in local (Eastern) zone as UTC, so evening classes keep
        # their final occurrence instead of it falling past a bare-UTC UNTIL.
        until_time = Time.zone.local(recurrence_end.year, recurrence_end.month, recurrence_end.day, 23, 59, 59).utc
        rule       = IceCube::Rule.weekly.day(day_sym).until(until_time)
        e.rrule    = rule.to_ical
      end
    end

    # The last change to anything that the class event shows. A calendar client
    # keeps its copy until LAST-MODIFIED or SEQUENCE goes up, so a new title
    # template, color, holiday, or room must move it too. Every row here is
    # already loaded, so this runs no query.
    def meeting_time_last_modified(course, meeting_time)
      [
        course.updated_at,
        meeting_time.updated_at,
        @preference_resolver.last_changed_at_for(meeting_time),
        *meeting_time.course.faculties.map(&:updated_at),
        *meeting_time.meeting_time_rooms.map(&:updated_at),
        *meeting_time.rooms.map(&:updated_at),
        *meeting_time.rooms.filter_map { |room| room.building&.updated_at },
        *@holidays.for(meeting_time).map(&:updated_at)
      ].compact.max
    end

    def parse_time(date, time_int)
      return nil unless date && time_int

      hours   = time_int / 100
      minutes = time_int % 100
      Time.zone.local(date.year, date.month, date.day, hours, minutes)
    end

    def find_first_meeting_date(meeting_time)
      return nil if meeting_time.day_of_week.blank?

      target_wday  = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
      current_date = meeting_time.start_date.to_date

      7.times do
        return current_date if current_date.wday == target_wday

        current_date += 1.day
      end

      nil
    end
  end
end
