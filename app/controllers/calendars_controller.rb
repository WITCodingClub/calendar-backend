class CalendarsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    @user = User.find_by!(calendar_token: params[:calendar_token])

    # Get all enrolled courses (filtering by meeting_times dates will be handled in the iCal RRULE)
    @courses = @user.courses
                    .includes(:meeting_times, :term, meeting_times: [:room, :building])

    respond_to do |format|
      format.ics do
        calendar = generate_ical(@courses)
        render plain: calendar.to_ical, content_type: "text/calendar"
      end
    end
  end

  private

  def generate_ical(courses)
    require "icalendar"

    cal = Icalendar::Calendar.new
    cal.prodid = "-//WITCC//Course Calendar//EN"
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

    cal.common_name

    courses.each do |course|
      course.meeting_times.each do |meeting_time|
        # Get the days this class meets
        days = get_meeting_days(meeting_time)
        next if days.empty?

        # Create event for this meeting time
        cal.event do |e|
          # Find the first day that matches one of the meeting days
          first_meeting_date = find_first_meeting_date(meeting_time)
          next unless first_meeting_date

          # Convert integer times (e.g., 900 = 9:00 AM) to Time objects
          start_time = parse_time(first_meeting_date, meeting_time.begin_time)
          end_time = parse_time(first_meeting_date, meeting_time.end_time)

          e.dtstart = Icalendar::Values::DateTime.new(start_time)
          e.dtend = Icalendar::Values::DateTime.new(end_time)

          # Course title with section
          e.summary = "#{course.subject} #{course.course_number}-#{course.section_number}: #{course.title}"

          # Location
          if meeting_time.room && meeting_time.building
            e.location = "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
          elsif meeting_time.room
            e.location = meeting_time.room.name
          end

          # Recurring rule for days of the week
          e.rrule = "FREQ=WEEKLY;BYDAY=#{days.join(',')};UNTIL=#{meeting_time.end_date.strftime('%Y%m%dT%H%M%SZ')}"

          # Stable UID for consistent event identity across refreshes
          e.uid = "course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu"
          e.ip_class = "PRIVATE"

          # Timestamps for change detection
          e.dtstamp = Icalendar::Values::DateTime.new(Time.current)

          # Use the most recent update time between course and meeting_time
          last_modified = [course.updated_at, meeting_time.updated_at].max
          e.last_modified = Icalendar::Values::DateTime.new(last_modified)

          # Sequence number based on update timestamps (helps clients detect changes)
          # Using seconds since epoch divided by 60 to get a stable incrementing number
          e.sequence = (last_modified.to_i / 60)
        end
      end
    end

    cal.publish

    cal
  end

  def get_meeting_days(meeting_time)
    days = []
    days << "MO" if meeting_time.monday
    days << "TU" if meeting_time.tuesday
    days << "WE" if meeting_time.wednesday
    days << "TH" if meeting_time.thursday
    days << "FR" if meeting_time.friday
    days << "SA" if meeting_time.saturday
    days << "SU" if meeting_time.sunday
    days
  end

  def parse_time(date, time_int)
    return nil unless date && time_int

    # Convert integer time (e.g., 900 = 9:00 AM, 1330 = 1:30 PM)
    hours = time_int / 100
    minutes = time_int % 100

    Time.zone.local(date.year, date.month, date.day, hours, minutes)
  end

  def find_first_meeting_date(meeting_time)
    # Map day booleans to wday numbers (0=Sunday, 1=Monday, etc.)
    meeting_wdays = []
    meeting_wdays << 0 if meeting_time.sunday
    meeting_wdays << 1 if meeting_time.monday
    meeting_wdays << 2 if meeting_time.tuesday
    meeting_wdays << 3 if meeting_time.wednesday
    meeting_wdays << 4 if meeting_time.thursday
    meeting_wdays << 5 if meeting_time.friday
    meeting_wdays << 6 if meeting_time.saturday

    return nil if meeting_wdays.empty?

    # Start from the meeting start_date
    current_date = meeting_time.start_date.to_date

    # Find the first day that matches one of the meeting days (max 7 days search)
    7.times do
      return current_date if meeting_wdays.include?(current_date.wday)
      current_date += 1.day
    end

    nil
  end
end