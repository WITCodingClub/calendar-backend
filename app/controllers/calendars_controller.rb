class CalendarsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    @user = User.find_by!(calendar_token: params[:calendar_token])

    # Get all enrolled courses (filtering by meeting_times dates will be handled in the iCal RRULE)
    @courses = @user.courses
                    .includes(:meeting_times, meeting_times: [ :room, :building ])

    respond_to do |format|
      format.ics do
        calendar = generate_ical(@courses)

        # Add cache control headers to suggest refresh intervals
        response.headers["Cache-Control"] = "max-age=3600, must-revalidate" # 1 hour
        response.headers["X-Published-TTL"] = "PT1H" # iCalendar refresh hint (1 hour)
        response.headers["Refresh-Interval"] = "3600" # Alternative hint

        render plain: calendar.to_ical, content_type: "text/calendar"
      end
    end
  end

  private

  def generate_ical(courses)
    require "icalendar"

    cal = Icalendar::Calendar.new
    cal.prodid = "-//WITCC//Course Calendar//EN"
    cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
    cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.email}")

      cal.timezone do |t|
      t.tzid = "America/New_York"

      t.daylight do |d|
        d.tzoffsetfrom = "-0600"
        d.tzoffsetto   = "-0500"
        d.tzname       = "EDT"
        d.dtstart      = "19700308T020000"
        d.rrule        = "FREQ=YEARLY;BYMONTH=3;BYDAY=2SU"
      end

      t.standard do |s|
        s.tzoffsetfrom = "-0500"
        s.tzoffsetto   = "-0600"
        s.tzname       = "EST"
        s.dtstart      = "19701101T020000"
        s.rrule        = "FREQ=YEARLY;BYMONTH=11;BYDAY=1SU"
      end
    end

    courses.each do |course|
      course.meeting_times.each do |meeting_time|
        # Skip if day_of_week is not set
        next unless meeting_time.day_of_week.present?

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

          e.dtstart = Icalendar::Values::DateTime.new(start_time)
          e.dtend = Icalendar::Values::DateTime.new(end_time)

          # Course title with section
          e.summary = course.title

          # Location
          if meeting_time.room && meeting_time.building
            e.location = "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
          elsif meeting_time.room
            e.location = meeting_time.room.name
          end

          # Recurring rule for this specific day of the week
          # Each meeting_time now represents a single day
          e.rrule = "FREQ=WEEKLY;BYDAY=#{day_code};UNTIL=#{meeting_time.end_date.strftime('%Y%m%dT%H%M%SZ')}"

          # Stable UID for consistent event identity across refreshes
          e.uid = "course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu"

          e.color = "##{meeting_time.event_color}" if meeting_time.event_color.present?

          # Timestamps for change detection
          e.dtstamp = Icalendar::Values::DateTime.new(Time.current)

          if meeting_time.event_color.present?
            e.append_custom_property("X-APPLE-CALENDAR-COLOR", "##{meeting_time.event_color}")
            e.append_custom_property("COLOR", "#{meeting_time.event_color}")
          end

          # Use the most recent update time between course and meeting_time
          last_modified = [ course.updated_at, meeting_time.updated_at ].max
          e.last_modified = Icalendar::Values::DateTime.new(last_modified)

          # Sequence number based on update timestamps (helps clients detect changes)
          # Using seconds since epoch divided by 60 to get a stable incrementing number
          e.sequence = (last_modified.to_i / 60)

        end
      end
    end

    cal
  end

  def get_day_code(meeting_time)
    return nil unless meeting_time.day_of_week.present?

    # Map day_of_week enum to RFC 5545 day codes
    day_codes = {
      "sunday" => "SU",
      "monday" => "MO",
      "tuesday" => "TU",
      "wednesday" => "WE",
      "thursday" => "TH",
      "friday" => "FR",
      "saturday" => "SA"
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
    return nil unless meeting_time.day_of_week.present?

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
end
