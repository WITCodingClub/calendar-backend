# frozen_string_literal: true

module CourseScheduleSyncable
  extend ActiveSupport::Concern

  def sync_course_schedule(force: false)
    service = GoogleCalendarService.new(self)

    # Build events from enrollments - each course can have multiple meeting times
    # Each meeting_time now represents a single day of the week
    events = []

    enrollments.includes(course: [meeting_times: [:room, :building]]).find_each do |enrollment|
      course = enrollment.course

      course.meeting_times.each do |meeting_time|
        # Skip if day_of_week is not set
        next if meeting_time.day_of_week.blank?

        # Find the first date this class actually meets
        first_meeting_date = find_first_meeting_date(meeting_time)
        next unless first_meeting_date

        # Convert integer times (e.g., 900 = 9:00 AM) to DateTime objects
        start_time = parse_time(first_meeting_date, meeting_time.begin_time)
        end_time = parse_time(first_meeting_date, meeting_time.end_time)
        next unless start_time && end_time

        # Build location string
        location = if meeting_time.room && meeting_time.building
                     "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
                   elsif meeting_time.room
                     meeting_time.room.name
                   end

        # Build course code from subject-number-section
        course_code = [course.subject, course.course_number, course.section_number].compact.join("-")

        # Build recurrence rule for weekly repeating events
        recurrence_rule = build_recurrence_rule(meeting_time)

        events << {
          summary: course.title,
          description: course_code,
          location: location,
          start_time: start_time,
          end_time: end_time,
          course_code: course_code,
          meeting_time_id: meeting_time.id,
          recurrence: recurrence_rule ? [recurrence_rule] : nil
        }
      end
    end

    service.update_calendar_events(events, force: force)
  end

  # Intelligent partial sync - only sync specific enrollments
  def sync_enrollments(enrollment_ids, force: false)
    service = GoogleCalendarService.new(self)
    events = []

    enrollments.where(id: enrollment_ids).includes(course: [meeting_times: [:room, :building]]).find_each do |enrollment|
      course = enrollment.course

      course.meeting_times.each do |meeting_time|
        next if meeting_time.day_of_week.blank?

        first_meeting_date = find_first_meeting_date(meeting_time)
        next unless first_meeting_date

        start_time = parse_time(first_meeting_date, meeting_time.begin_time)
        end_time = parse_time(first_meeting_date, meeting_time.end_time)
        next unless start_time && end_time

        location = if meeting_time.room && meeting_time.building
                     "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
                   elsif meeting_time.room
                     meeting_time.room.name
                   end

        course_code = [course.subject, course.course_number, course.section_number].compact.join("-")
        recurrence_rule = build_recurrence_rule(meeting_time)

        events << {
          summary: course.title,
          description: course_code,
          location: location,
          start_time: start_time,
          end_time: end_time,
          course_code: course_code,
          meeting_time_id: meeting_time.id,
          recurrence: recurrence_rule ? [recurrence_rule] : nil
        }
      end
    end

    # Only sync these specific events
    service.update_specific_events(events, force: force)
  end

  # Quick sync - only update stale events (not synced in last hour)
  def quick_sync
    sync_course_schedule(force: false)
  end

  # Force sync - update all events regardless of staleness
  def force_sync
    sync_course_schedule(force: true)
  end

  def find_first_meeting_date(meeting_time)
    return nil if meeting_time.day_of_week.blank?

    # Get the numeric day of week (0=Sunday, 1=Monday, etc.)
    # The enum value is already stored as the integer wday value
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

  def parse_time(date, time_int)
    return nil unless date && time_int

    # Convert integer time (e.g., 900 = 9:00 AM, 1330 = 1:30 PM)
    hours = time_int / 100
    minutes = time_int % 100

    # Create time in configured timezone (Eastern Time)
    Time.zone.local(date.year, date.month, date.day, hours, minutes)
  end

  def build_recurrence_rule(meeting_time)
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

    day_code = day_codes[meeting_time.day_of_week]
    return nil unless day_code

    # Format: RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20240515T235959Z
    # Each meeting_time now represents a single day, so only one day code
    until_date = meeting_time.end_date.strftime("%Y%m%dT235959Z")
    "RRULE:FREQ=WEEKLY;BYDAY=#{day_code};UNTIL=#{until_date}"
  end

  # Add a method to handle calendar deletion/cleanup
  def delete_course_calendar
    google_calendar = google_credential&.google_calendar
    return if google_calendar.blank?

    service = GoogleCalendarService.new(self)
    service_account_service = service.send(:service_account_calendar_service)

    service_account_service.delete_calendar(google_calendar.google_calendar_id)

    # Destroy the GoogleCalendar record (this will cascade delete all associated events)
    google_calendar.destroy
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to delete calendar: #{e.message}"
  end

  def create_or_get_course_calendar
    GoogleCalendarService.new(self).create_or_get_course_calendar
  end
end
