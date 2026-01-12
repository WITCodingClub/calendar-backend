# frozen_string_literal: true

class CalendarsController < ApplicationController
  include ApplicationHelper

  skip_before_action :verify_authenticity_token

  def show
    @user = User.find_by!(calendar_token: params[:calendar_token])

    # Get all enrolled courses with meeting times
    @courses = @user.courses
                    .includes(:meeting_times, :term, meeting_times: [:room, :building])

    # Get final exams for enrolled courses
    @final_exams = FinalExam.where(course_id: @courses.pluck(:id))
                            .where(exam_date: Time.zone.today..)
                            .includes(:course)

    respond_to do |format|
      format.ics do
        calendar = generate_ical(@courses, @final_exams)

        # Add cache control headers to suggest refresh intervals
        response.headers["Cache-Control"] = "max-age=3600, must-revalidate" # 1 hour
        response.headers["X-Published-TTL"] = "PT1H" # iCalendar refresh hint (1 hour)
        response.headers["Refresh-Interval"] = "3600" # Alternative hint

        render plain: calendar.to_ical, content_type: "text/calendar"
      end
    end
  end

  private

  def generate_ical(courses, final_exams)
    require "icalendar"

    # Initialize preference resolver and template renderer for this user
    @preference_resolver = PreferenceResolver.new(@user)
    @template_renderer = CalendarTemplateRenderer.new

    # Cache holidays for EXDATE generation
    @holidays_cache = {}

    cal = Icalendar::Calendar.new
    cal.prodid = "-//WITCC//Course Calendar//EN"
    cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
    cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.email}")

    cal.timezone do |t|
      t.tzid = "America/New_York"

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

    courses.each do |course|
      # Filter meeting times to prefer valid locations over TBD duplicates
      filtered_meeting_times = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                                     .map do |key, meeting_times|
                                       # If multiple meeting times exist for same day/time, prefer non-TBD over TBD
                                       non_tbd = meeting_times.reject { |mt| (mt.building && @user.send(:tbd_building?, mt.building)) || (mt.room && @user.send(:tbd_room?, mt.room)) }
                                       non_tbd.any? ? non_tbd.first : meeting_times.first
      end

      filtered_meeting_times.each do |meeting_time|
        # Skip if day_of_week is not set
        next if meeting_time.day_of_week.blank?

        # Get the day code for this meeting time
        day_code = get_day_code(meeting_time)
        next unless day_code

        # Create event for this meeting time
        cal.event do |e|
          # Find the first day that matches the meeting day
          first_meeting_date = find_first_meeting_date(meeting_time)
          next unless first_meeting_date

          # Convert integer times (e.g., 900 = 9:00 AM) to Time objects
          start_time = parse_time(first_meeting_date, meeting_time.begin_time)
          end_time = parse_time(first_meeting_date, meeting_time.end_time)

          # Check if this is an all-day event (12:01pm-11:59pm in university calendar)
          if meeting_time.all_day?
            e.dtstart = Icalendar::Values::Date.new(first_meeting_date)
            e.dtend = Icalendar::Values::Date.new(first_meeting_date + 1.day) # ICS all-day end is exclusive
          else
            e.dtstart = Icalendar::Values::DateTime.new(start_time, tzid: "America/New_York")
            e.dtend = Icalendar::Values::DateTime.new(end_time, tzid: "America/New_York")
          end

          # Resolve user preferences for this meeting time
          prefs = @preference_resolver.resolve_for(meeting_time)
          context = CalendarTemplateRenderer.build_context_from_meeting_time(meeting_time)

          # Apply title template (or fallback to course title)
          if prefs[:title_template].present?
            e.summary = @template_renderer.render(prefs[:title_template], context)
          else
            e.summary = titleize_with_roman_numerals(course.title)
          end

          # Apply description template if set
          if prefs[:description_template].present?
            e.description = @template_renderer.render(prefs[:description_template], context)
          end

          # Location - handle TBD locations gracefully
          if meeting_time.room && meeting_time.building &&
             !@user.send(:tbd_location?, meeting_time.building, meeting_time.room)
            # Valid room and building
            e.location = "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
          elsif meeting_time.room && !@user.send(:tbd_room?, meeting_time.room)
            # Valid room, no building or invalid building
            e.location = meeting_time.room.formatted_number
          elsif @user.send(:tbd_building?, meeting_time.building) || @user.send(:tbd_room?, meeting_time.room)
            # TBD location - show "TBD" instead of ugly "To Be Determined 000"
            e.location = "TBD"
          else
            # No location info
            e.location = nil
          end

          # Recurring rule for this specific day of the week
          # Each meeting_time now represents a single day
          if meeting_time.all_day?
            # For all-day events, use date format for UNTIL
            until_date = meeting_time.end_date.to_date
            e.rrule = "FREQ=WEEKLY;BYDAY=#{day_code};UNTIL=#{until_date.strftime('%Y%m%d')}"
          else
            # For timed events, use datetime format for UNTIL (235959 = end of day in Eastern Time)
            until_datetime = Time.zone.local(meeting_time.end_date.year, meeting_time.end_date.month, meeting_time.end_date.day, 23, 59, 59)
            e.rrule = "FREQ=WEEKLY;BYDAY=#{day_code};UNTIL=#{until_datetime.strftime('%Y%m%dT%H%M%S')}"
          end

          # Add EXDATE entries for holidays to skip class on those days
          holiday_exdates = build_holiday_exdates_for_meeting_time(meeting_time, start_time)
          holiday_exdates.each do |exdate|
            if meeting_time.all_day?
              e.append_exdate(Icalendar::Values::Date.new(exdate.to_date))
            else
              e.append_exdate(Icalendar::Values::DateTime.new(exdate, tzid: "America/New_York"))
            end
          end

          # Stable UID for consistent event identity across refreshes
          e.uid = "course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu"

          # Use preference color if set, otherwise use meeting_time default
          color_hex = if prefs[:color_id].present?
                        get_google_color_hex(prefs[:color_id])
                      elsif meeting_time.event_color.present?
                        meeting_time.event_color
                      end

          if color_hex
            e.color = "##{color_hex}"
          end

          # Timestamps for change detection
          e.dtstamp = Icalendar::Values::DateTime.new(Time.current, tzid: "America/New_York")

          if color_hex
            e.append_custom_property("X-APPLE-CALENDAR-COLOR", "##{color_hex}")
            e.append_custom_property("COLOR", color_hex.to_s)
          end

          # Use the most recent update time between course and meeting_time
          last_modified = [course.updated_at, meeting_time.updated_at].max
          e.last_modified = Icalendar::Values::DateTime.new(last_modified, tzid: "America/New_York")

          # Sequence number based on update timestamps (helps clients detect changes)
          # Using seconds since epoch divided by 60 to get a stable incrementing number
          e.sequence = (last_modified.to_i / 60)

        end
      end
    end

    # Add final exam events
    add_final_exam_events(cal, final_exams)

    # Add university calendar events (holidays always, others if opted in)
    add_university_events(cal)

    cal
  end

  # Add final exam events to the calendar
  def add_final_exam_events(cal, final_exams)
    final_exams.each do |final_exam|
      next unless final_exam.start_datetime && final_exam.end_datetime

      cal.event do |e|
        e.dtstart = Icalendar::Values::DateTime.new(final_exam.start_datetime, tzid: "America/New_York")
        e.dtend = Icalendar::Values::DateTime.new(final_exam.end_datetime, tzid: "America/New_York")

        e.summary = "Final Exam: #{titleize_with_roman_numerals(final_exam.course_title)}"
        e.description = final_exam.course_code
        e.location = final_exam.location if final_exam.location.present?

        # Stable UID for final exams
        e.uid = "final-exam-#{final_exam.id}@calendar-util.wit.edu"

        e.dtstamp = Icalendar::Values::DateTime.new(Time.current, tzid: "America/New_York")
        e.last_modified = Icalendar::Values::DateTime.new(final_exam.updated_at, tzid: "America/New_York")
        e.sequence = (final_exam.updated_at.to_i / 60)
      end
    end
  end

  # Add university calendar events (holidays auto-sync, others based on user preference)
  def add_university_events(cal)
    # Always include holidays (auto-sync for all users)
    UniversityCalendarEvent.holidays.upcoming.find_each do |event|
      add_university_event_to_calendar(cal, event, force_all_day: true)
    end

    # Include other categories only if user opted in
    user_config = @user.user_extension_config
    return unless user_config&.sync_university_events

    categories = (user_config.university_event_categories || []) - ["holiday"]
    return if categories.empty?

    UniversityCalendarEvent.upcoming.by_categories(categories).find_each do |event|
      add_university_event_to_calendar(cal, event)
    end
  end

  # Add a single university event to the calendar
  def add_university_event_to_calendar(cal, event, force_all_day: false)
    cal.event do |e|
      # Force holidays to be all-day events regardless of database value
      is_all_day = force_all_day || event.all_day || event.category == "holiday"

      if is_all_day
        e.dtstart = Icalendar::Values::Date.new(event.start_time.to_date)
        e.dtend = Icalendar::Values::Date.new(event.end_time.to_date + 1.day) # ICS all-day is exclusive
      else
        e.dtstart = Icalendar::Values::DateTime.new(event.start_time, tzid: "America/New_York")
        e.dtend = Icalendar::Values::DateTime.new(event.end_time, tzid: "America/New_York")
      end

      # Add holiday prefix to make it clear in calendar apps
      if event.category == "holiday"
        e.summary = event.formatted_holiday_summary
      else
        e.summary = event.summary
      end

      e.description = event.description if event.description.present?
      e.location = event.location if event.location.present?

      # Stable UID based on ICS UID from source
      e.uid = "university-#{event.ics_uid}@calendar-util.wit.edu"

      e.dtstamp = Icalendar::Values::DateTime.new(Time.current, tzid: "America/New_York")
      e.last_modified = Icalendar::Values::DateTime.new(event.updated_at, tzid: "America/New_York")
      e.sequence = (event.updated_at.to_i / 60)

      # Add category as custom property
      e.categories = [event.category.titleize] if event.category.present?

      # Add custom properties to help calendar apps identify holidays
      if event.category == "holiday"
        e.append_custom_property("X-MICROSOFT-CDO-ALLDAYEVENT", "TRUE")
        e.append_custom_property("X-MICROSOFT-CDO-BUSYSTATUS", "FREE")
        e.transp = "TRANSPARENT" # Show as "free" time
      end
    end
  end

  # Build EXDATE times for holidays that fall on a meeting time's day
  def build_holiday_exdates_for_meeting_time(meeting_time, start_time)
    return [] unless defined?(UniversityCalendarEvent)

    target_wday = MeetingTime.day_of_weeks[meeting_time.day_of_week]
    return [] if target_wday.nil?

    # Get holidays for this date range (memoized)
    cache_key = [meeting_time.start_date, meeting_time.end_date]
    holidays = @holidays_cache[cache_key] ||= UniversityCalendarEvent.holidays_between(
      meeting_time.start_date,
      meeting_time.end_date
    ).to_a

    # Filter to holidays that fall on this day of week
    holidays.select { |h| h.start_time.wday == target_wday }
            .map do |h|
              # Build datetime with the holiday's date but the meeting's time
              Time.zone.local(
                h.start_time.year, h.start_time.month, h.start_time.day,
                start_time.hour, start_time.min, 0
              )
            end
  end

  def get_day_code(meeting_time)
    return nil if meeting_time.day_of_week.blank?

    # Map day_of_week enum to RFC 5545 day codes
    day_codes = {
      "sunday"    => "SU",
      "monday"    => "MO",
      "tuesday"   => "TU",
      "wednesday" => "WE",
      "thursday"  => "TH",
      "friday"    => "FR",
      "saturday"  => "SA"
    }

    day_codes[meeting_time.day_of_week]
  end

  def parse_time(date, time_int)
    return nil unless date && time_int

    # Convert integer time (e.g., 900 = 9:00 AM, 1330 = 1:30 PM)
    hours = time_int / 100
    minutes = time_int % 100

    Time.zone.local(date.year, date.month, date.day, hours, minutes)
  end

  def find_first_meeting_date(meeting_time)
    return nil if meeting_time.day_of_week.blank?

    # Get the numeric day of week (0=Sunday, 1=Monday, etc.)
    target_wday = MeetingTime.day_of_weeks[meeting_time.day_of_week]

    # Start from the meeting start_date
    current_date = meeting_time.start_date.to_date

    # Find the first day that matches the meeting day (max 7 days search)
    7.times do
      return current_date if current_date.wday == target_wday

      current_date += 1.day
    end

    nil
  end

  def get_google_color_hex(color_id)
    # Map Google Calendar color IDs (1-11) to hex colors
    # These match the Google Calendar color palette
    color_map = {
      1  => "A4BDFC",  # Lavender
      2  => "7AE7BF",  # Sage
      3  => "DBADFF",  # Grape
      4  => "FF887C",  # Flamingo
      5  => "FBD75B",  # Banana
      6  => "FFB878",  # Tangerine
      7  => "46D6DB",  # Peacock
      8  => "E1E1E1",  # Graphite
      9  => "5484ED",  # Blueberry
      10 => "51B749", # Basil
      11 => "DC2127"  # Tomato
    }

    color_map[color_id]
  end

end
