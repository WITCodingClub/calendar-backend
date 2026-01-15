# frozen_string_literal: true

module CourseScheduleSyncable
  extend ActiveSupport::Concern

  def sync_course_schedule(force: false)
    service = GoogleCalendarService.new(self)

    # Build events from enrollments - each course can have multiple meeting times
    # Each meeting_time now represents a single day of the week
    events = []

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    enrollments.includes(course: [meeting_times: [:room, :building]]).find_each do |enrollment|
      course = enrollment.course

      # Filter meeting times to prefer valid locations over TBD duplicates
      filtered_meeting_times = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                                     .map do |key, meeting_times|
                                       # If multiple meeting times exist for same day/time, prefer non-TBD over TBD
                                       non_tbd = meeting_times.reject { |mt| (mt.building && tbd_building?(mt.building)) || (mt.room && tbd_room?(mt.room)) }
                                       non_tbd.any? ? non_tbd.first : meeting_times.first
      end

      filtered_meeting_times.each do |meeting_time|
        # Skip if day_of_week is not set
        next if meeting_time.day_of_week.blank?

        # Find the first date this class actually meets
        first_meeting_date = find_first_meeting_date(meeting_time)
        next unless first_meeting_date

        # Convert integer times (e.g., 900 = 9:00 AM) to DateTime objects
        start_time = parse_time(first_meeting_date, meeting_time.begin_time)
        end_time = parse_time(first_meeting_date, meeting_time.end_time)
        next unless start_time && end_time

        # Build location string - handle TBD locations gracefully
        location = if meeting_time.room && meeting_time.building &&
                      !tbd_location?(meeting_time.building, meeting_time.room)
                     # Valid room and building
                     "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
                   elsif meeting_time.room && !tbd_room?(meeting_time.room)
                     # Valid room, no building or invalid building
                     meeting_time.room.formatted_number
                   elsif tbd_building?(meeting_time.building) || tbd_room?(meeting_time.room)
                     # TBD location - show "TBD" instead of ugly "To Be Determined 000"
                     "TBD"
                   else
                     # No location info
                     nil
                   end

        # Build course code from subject-number-section
        course_code = [course.subject, course.course_number, course.section_number].compact.join("-")

        # Build recurrence rule for weekly repeating events
        recurrence_rule = build_recurrence_rule(meeting_time)
        # Build recurrence with holiday exclusions
        recurrence = build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

        events << {
          summary: course.title,
          description: course_code,
          location: location,
          start_time: start_time,
          end_time: end_time,
          course_code: course_code,
          meeting_time_id: meeting_time.id,
          recurrence: recurrence,
          all_day: meeting_time.all_day?
        }
      end
    end

    # Add final exams for enrolled courses
    finals = build_finals_events_for_sync
    events.concat(finals)

    # Add university calendar events (holidays and other categories based on user preferences)
    university_events = build_university_events_for_sync
    events.concat(university_events)

    result = service.update_calendar_events(events, force: force)

    # Update last sync timestamp if sync was successful
    if result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)
      # rubocop:disable Rails/SkipsModelValidations
      update_columns(
        last_calendar_sync_at: Time.current,
        calendar_needs_sync: false
      )
      # rubocop:enable Rails/SkipsModelValidations
    end

    result
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

        # Build location string - handle TBD locations gracefully
        location = if meeting_time.room && meeting_time.building &&
                      !tbd_location?(meeting_time.building, meeting_time.room)
                     # Valid room and building
                     "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
                   elsif meeting_time.room && !tbd_room?(meeting_time.room)
                     # Valid room, no building or invalid building
                     meeting_time.room.formatted_number
                   elsif tbd_building?(meeting_time.building) || tbd_room?(meeting_time.room)
                     # TBD location - show "TBD" instead of ugly "To Be Determined 000"
                     "TBD"
                   else
                     # No location info
                     nil
                   end

        course_code = [course.subject, course.course_number, course.section_number].compact.join("-")
        recurrence_rule = build_recurrence_rule(meeting_time)
        recurrence = build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

        events << {
          summary: course.title,
          description: course_code,
          location: location,
          start_time: start_time,
          end_time: end_time,
          course_code: course_code,
          meeting_time_id: meeting_time.id,
          recurrence: recurrence,
          all_day: meeting_time.all_day?
        }
      end
    end

    # Only sync these specific events
    result = service.update_specific_events(events, force: force)

    # Update last sync timestamp if sync was successful
    if result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)
      # rubocop:disable Rails/SkipsModelValidations
      update_columns(
        last_calendar_sync_at: Time.current,
        calendar_needs_sync: false
      )
      # rubocop:enable Rails/SkipsModelValidations
    end

    result
  end

  # Sync a single meeting time immediately (for preference changes)
  def sync_meeting_time(meeting_time_id, force: true)
    service = GoogleCalendarService.new(self)
    meeting_time = MeetingTime.includes(course: [:faculties], room: :building).find_by(id: meeting_time_id)
    return unless meeting_time
    return if meeting_time.day_of_week.blank?

    first_meeting_date = find_first_meeting_date(meeting_time)
    return unless first_meeting_date

    start_time = parse_time(first_meeting_date, meeting_time.begin_time)
    end_time = parse_time(first_meeting_date, meeting_time.end_time)
    return unless start_time && end_time

    # Build location string - handle TBD locations gracefully
    location = if meeting_time.room && meeting_time.building &&
                  !tbd_location?(meeting_time.building, meeting_time.room)
                 # Valid room and building
                 "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
               elsif meeting_time.room && !tbd_room?(meeting_time.room)
                 # Valid room, no building or invalid building
                 meeting_time.room.formatted_number
               elsif tbd_building?(meeting_time.building) || tbd_room?(meeting_time.room)
                 # TBD location - show "TBD" instead of ugly "To Be Determined 000"
                 "TBD"
               else
                 # No location info
                 nil
               end

    course = meeting_time.course
    course_code = [course.subject, course.course_number, course.section_number].compact.join("-")
    recurrence_rule = build_recurrence_rule(meeting_time)
    recurrence = build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

    event = {
      summary: course.title,
      description: course_code,
      location: location,
      start_time: start_time,
      end_time: end_time,
      course_code: course_code,
      meeting_time_id: meeting_time.id,
      recurrence: recurrence,
      all_day: meeting_time.all_day?
    }

    # Sync just this one event
    result = service.update_specific_events([event], force: force)

    # Update last sync timestamp if sync was successful
    if result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)
      update_column(:last_calendar_sync_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    result
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

    # Determine the end date for recurrence
    # Use meeting_time.end_date, but stop before finals week if THIS COURSE has a final
    recurrence_end = meeting_time.end_date.to_date

    # Check if THIS SPECIFIC COURSE has a final exam - if so, end classes before finals start
    # Only adjust if the course actually has a final exam scheduled
    course = meeting_time.course
    if course
      course_final = final_exam_date_for_course(course.id)
      if course_final && course_final < recurrence_end
        # End classes the day before this course's final exam
        recurrence_end = course_final - 1.day
      end
    end

    # Format: RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20240515T235959Z
    # Each meeting_time now represents a single day, so only one day code
    until_date = recurrence_end.strftime("%Y%m%dT235959Z")
    "RRULE:FREQ=WEEKLY;BYDAY=#{day_code};UNTIL=#{until_date}"
  end

  # Memoized lookup of final exam date for a specific course
  # Avoids N+1 queries when building recurrence rules for multiple meeting times
  # Returns nil if the course doesn't have a final exam
  def final_exam_date_for_course(course_id)
    @course_final_dates ||= {}
    @course_final_dates[course_id] ||= ::FinalExam.where(course_id: course_id)
                                                  .where.not(exam_date: nil)
                                                  .minimum(:exam_date)
  end

  # Build recurrence array with RRULE and EXDATE entries for holidays
  # @param meeting_time [MeetingTime] The meeting time object
  # @param recurrence_rule [String, nil] The RRULE string
  # @param start_time [Time] The start time of the first meeting
  # @return [Array<String>, nil] Array of recurrence rules including EXDATEs, or nil
  def build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)
    return nil unless recurrence_rule

    recurrence = [recurrence_rule]

    # Get holiday dates that should be excluded from this meeting time
    exdates = build_holiday_exdates(meeting_time, start_time)
    recurrence.concat(exdates) if exdates.any?

    recurrence
  end

  # Build EXDATE strings for holidays that fall on this meeting time's day
  # @param meeting_time [MeetingTime] The meeting time object
  # @param start_time [Time] The start time of meetings (for time component)
  # @return [Array<String>] Array of EXDATE strings
  def build_holiday_exdates(meeting_time, start_time)
    return [] unless defined?(UniversityCalendarEvent)

    # Get the numeric day of week (0=Sunday, 1=Monday, etc.)
    target_wday = MeetingTime.day_of_weeks[meeting_time.day_of_week]
    return [] if target_wday.nil?

    # Get all holidays during the course date range
    holidays = holidays_for_meeting_time(meeting_time)
    return [] if holidays.empty?

    # Filter to holidays that have any day falling on this meeting day
    matching_holidays = holidays.select do |holiday|
      if holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date
        # Multi-day event: check if any day in the range matches target weekday
        (holiday.start_time.to_date..holiday.end_time.to_date).any? { |date| date.wday == target_wday }
      else
        # Single-day event: check if the day matches
        holiday.start_time.wday == target_wday
      end
    end

    # Build EXDATE strings for all matching dates
    exdates = []
    matching_holidays.each do |holiday|
      if holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date
        # Multi-day: add EXDATE for each matching weekday in the range
        (holiday.start_time.to_date..holiday.end_time.to_date).each do |date|
          exdates << format_exdate(date, start_time) if date.wday == target_wday
        end
      else
        # Single-day: add one EXDATE
        exdates << format_exdate(holiday.start_time.to_date, start_time)
      end
    end

    exdates
  end

  # Get holidays that apply to a meeting time's date range
  # Memoized to avoid repeated queries when processing multiple meeting times
  # @param meeting_time [MeetingTime] The meeting time to get holidays for
  # @return [Array<UniversityCalendarEvent>] Holiday events in the date range
  def holidays_for_meeting_time(meeting_time)
    @holidays_cache ||= {}
    cache_key = [meeting_time.start_date, meeting_time.end_date]

    @holidays_cache[cache_key] ||= UniversityCalendarEvent.holidays_between(
      meeting_time.start_date,
      meeting_time.end_date
    ).to_a
  end

  # Format an EXDATE string for Google Calendar
  # Uses date-time format matching the event's start time
  # @param date [Date] The date to exclude
  # @param start_time [Time] The event start time (for hour/minute)
  # @return [String] Formatted EXDATE string
  def format_exdate(date, start_time)
    # Build the exclusion datetime using the date and the meeting's time
    exclusion_time = Time.zone.local(
      date.year, date.month, date.day,
      start_time.hour, start_time.min, 0
    )

    # Format as EXDATE with timezone
    # Google Calendar expects: EXDATE;TZID=America/New_York:20241128T090000
    timezone = Time.zone.tzinfo.name
    formatted_time = exclusion_time.strftime("%Y%m%dT%H%M%S")
    "EXDATE;TZID=#{timezone}:#{formatted_time}"
  end

  # Build university calendar events for sync (holidays always, others based on preferences)
  def build_university_events_for_sync
    events = []

    # Always include holidays (auto-sync for all users)
    UniversityCalendarEvent.holidays.upcoming.find_each do |event|
      events << {
        summary: event.formatted_holiday_summary,
        description: event.description,
        location: event.location,
        start_time: event.start_time,
        end_time: event.end_time,
        university_calendar_event_id: event.id,
        all_day: true,
        recurrence: nil
      }
    end

    # Include other categories only if user opted in
    user_config = user_extension_config
    if user_config&.sync_university_events
      categories = (user_config.university_event_categories || []) - ["holiday"]
      unless categories.empty?
        UniversityCalendarEvent.upcoming.by_categories(categories).find_each do |event|
          events << {
            summary: event.summary,
            description: event.description,
            location: event.location,
            start_time: event.start_time,
            end_time: event.end_time,
            university_calendar_event_id: event.id,
            all_day: event.all_day || false,
            recurrence: nil
          }
        end
      end
    end

    events
  end

  # Build events for final exams of enrolled courses
  # Only includes upcoming finals (today or future) - use sync_finals_for_term rake task for historical
  def build_finals_events_for_sync
    finals = []

    enrolled_course_ids = enrollments.pluck(:course_id)
    return finals if enrolled_course_ids.empty?

    # Only include finals that haven't happened yet (or are today)
    ::FinalExam.where(course_id: enrolled_course_ids)
               .where(exam_date: Time.zone.today..)
               .includes(course: :faculties)
               .find_each do |final_exam|
                 next unless final_exam.start_datetime && final_exam.end_datetime

                 finals << {
                   summary: "Final Exam: #{final_exam.course_title}",
                   description: final_exam.course_code,
                   location: final_exam.location,
                   start_time: final_exam.start_datetime,
                   end_time: final_exam.end_datetime,
                   course_code: final_exam.course_code,
                   final_exam_id: final_exam.id,
                   recurrence: nil # Finals don't recur
                 }
    end

    finals
  end

  # Sync a single final exam immediately (for preference changes)
  def sync_final_exam(final_exam_id, force: true)
    service = GoogleCalendarService.new(self)
    final_exam = ::FinalExam.includes(course: :faculties).find_by(id: final_exam_id)
    return unless final_exam
    return unless final_exam.start_datetime && final_exam.end_datetime

    event = {
      summary: "Final Exam: #{final_exam.course_title}",
      description: final_exam.course_code,
      location: final_exam.location,
      start_time: final_exam.start_datetime,
      end_time: final_exam.end_datetime,
      course_code: final_exam.course_code,
      final_exam_id: final_exam.id,
      recurrence: nil
    }

    result = service.update_specific_events([event], force: force)

    # Update last sync timestamp if sync was successful
    if result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)
      update_column(:last_calendar_sync_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    result
  end

  # Add a method to handle calendar deletion/cleanup
  def delete_course_calendar
    google_calendar = GoogleCalendar.for_user(self).first
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

  # Check if this is a TBD/placeholder location that should be skipped
  def tbd_location?(building, room)
    tbd_building?(building) || tbd_room?(room)
  end

  # Check if building is TBD/placeholder
  # LeopardWeb sends null/empty for unassigned locations, not "TBD" placeholders
  def tbd_building?(building)
    return false unless building

    # Empty/blank building means location not yet assigned
    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  # Check if room is TBD/placeholder (room 0 or room name contains TBD)
  def tbd_room?(room)
    return false unless room

    room.number == 0
    # Note: Room model in production only has 'number', not 'name'
    # If room.name is added later, uncomment these lines:
    # room.name&.downcase&.include?("tbd") ||
    # room.name&.downcase&.include?("to be determined")
  end
end
