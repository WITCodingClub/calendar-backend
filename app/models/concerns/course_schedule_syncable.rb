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

    # Add final exams for enrolled courses
    finals = build_finals_events_for_sync
    events.concat(finals)

    # Track events built for sync
    StatsD.gauge("sync.events_built", events.count, tags: ["user_id:#{id}", "force:#{force}"])
    StatsD.gauge("sync.finals_built", finals.count, tags: ["user_id:#{id}"])

    result = service.update_calendar_events(events, force: force)

    # Track sync completion
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    StatsD.measure("sync.full_sync.duration", duration, tags: ["user_id:#{id}", "force:#{force}"])

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

  # Sync a single meeting time immediately (for preference changes)
  def sync_meeting_time(meeting_time_id, force: true)
    # Track individual meeting time sync
    StatsD.increment("sync.meeting_time.synced", tags: ["user_id:#{id}", "meeting_time_id:#{meeting_time_id}"])

    service = GoogleCalendarService.new(self)
    meeting_time = MeetingTime.includes(course: [:faculties], room: :building).find_by(id: meeting_time_id)
    return unless meeting_time
    return if meeting_time.day_of_week.blank?

    first_meeting_date = find_first_meeting_date(meeting_time)
    return unless first_meeting_date

    start_time = parse_time(first_meeting_date, meeting_time.begin_time)
    end_time = parse_time(first_meeting_date, meeting_time.end_time)
    return unless start_time && end_time

    location = if meeting_time.room && meeting_time.building
                 "#{meeting_time.building.name} - #{meeting_time.room.formatted_number}"
               elsif meeting_time.room
                 meeting_time.room.name
               end

    course = meeting_time.course
    course_code = [course.subject, course.course_number, course.section_number].compact.join("-")
    recurrence_rule = build_recurrence_rule(meeting_time)

    event = {
      summary: course.title,
      description: course_code,
      location: location,
      start_time: start_time,
      end_time: end_time,
      course_code: course_code,
      meeting_time_id: meeting_time.id,
      recurrence: recurrence_rule ? [recurrence_rule] : nil
    }

    # Sync just this one event
    service.update_specific_events([event], force: force)
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

  # Build events for final exams of enrolled courses
  def build_finals_events_for_sync
    finals = []

    # Get current and next term to include their finals
    current_term = Term.current
    next_term = Term.next
    term_ids = [current_term&.id, next_term&.id].compact

    return finals if term_ids.empty?

    # Get finals for enrolled courses in current/next term
    enrolled_course_ids = enrollments.joins(:course)
                                     .where(courses: { term_id: term_ids })
                                     .pluck(:course_id)

    FinalExam.where(course_id: enrolled_course_ids)
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
    StatsD.increment("sync.final_exam.synced", tags: ["user_id:#{id}", "final_exam_id:#{final_exam_id}"])

    service = GoogleCalendarService.new(self)
    final_exam = FinalExam.includes(course: :faculties).find_by(id: final_exam_id)
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

    service.update_specific_events([event], force: force)
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
