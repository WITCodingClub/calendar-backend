# frozen_string_literal: true

namespace :calendar do
  desc "Find and report orphaned Google Calendar events"
  task find_orphaned_events: :environment do
    puts "Searching for orphaned Google Calendar events..."
    puts "=" * 60

    orphaned = {
      missing_meeting_times:      [],
      missing_final_exams:        [],
      missing_university_events:  [],
      unenrolled_courses:         [],
      past_events:                []
    }

    GoogleCalendarEvent.includes(
      :meeting_time, :final_exam, :university_calendar_event,
      google_calendar: :user
    ).find_each do |event|
      user = event.google_calendar&.user

      if event.meeting_time_id.present? && event.meeting_time.nil?
        orphaned[:missing_meeting_times] << event
        puts "Event #{event.id}: Missing meeting_time #{event.meeting_time_id} for user #{user&.id}"
      elsif event.final_exam_id.present? && event.final_exam.nil?
        orphaned[:missing_final_exams] << event
        puts "Event #{event.id}: Missing final_exam #{event.final_exam_id} for user #{user&.id}"
      elsif event.university_calendar_event_id.present? && event.university_calendar_event.nil?
        orphaned[:missing_university_events] << event
        puts "Event #{event.id}: Missing university_event #{event.university_calendar_event_id} for user #{user&.id}"
      end

      if event.meeting_time_id.present? && event.meeting_time.present?
        course = event.meeting_time.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned[:unenrolled_courses] << event
          puts "Event #{event.id}: User #{user.id} no longer enrolled in #{course.title}"
        end
      elsif event.final_exam_id.present? && event.final_exam.present?
        course = event.final_exam.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned[:unenrolled_courses] << event
        end
      end

      orphaned[:past_events] << event if event.end_time && event.end_time < 6.months.ago
    end

    puts "\n=== Orphaned Events Summary ==="
    puts "Missing meeting times:     #{orphaned[:missing_meeting_times].size}"
    puts "Missing final exams:       #{orphaned[:missing_final_exams].size}"
    puts "Missing university events: #{orphaned[:missing_university_events].size}"
    puts "Unenrolled courses:        #{orphaned[:unenrolled_courses].size}"
    puts "Old events (>6 months):    #{orphaned[:past_events].size}"
    puts "\nTotal unique orphaned:     #{orphaned.values.flatten.uniq.size}"

    total = orphaned.values.flatten.uniq.size
    puts "\nRun 'rake calendar:clean_orphaned_events' to remove these events" if total > 0
  end

  desc "Clean up orphaned Google Calendar events"
  task clean_orphaned_events: :environment do
    puts "Cleaning up orphaned Google Calendar events..."
    puts "=" * 60

    deleted_count = 0
    error_count   = 0

    orphaned_events = GoogleCalendarEvent
      .includes(:meeting_time, :final_exam, :university_calendar_event, google_calendar: :user)
      .find_each
      .select do |event|
        user = event.google_calendar&.user

        missing_assoc = (event.meeting_time_id.present? && event.meeting_time.nil?) ||
                        (event.final_exam_id.present? && event.final_exam.nil?) ||
                        (event.university_calendar_event_id.present? && event.university_calendar_event.nil?)
        next true if missing_assoc

        if event.meeting_time_id.present? && event.meeting_time.present?
          course = event.meeting_time.course
          course && user && !user.enrollments.exists?(course_id: course.id)
        elsif event.final_exam_id.present? && event.final_exam.present?
          course = event.final_exam.course
          course && user && !user.enrollments.exists?(course_id: course.id)
        else
          false
        end
      end

    events_by_user = orphaned_events.group_by { |e| e.google_calendar&.user }

    events_by_user.each do |user, events|
      next unless user

      puts "Processing #{events.size} orphaned events for user #{user.id} (#{user.email})..."
      service = GoogleCalendarService.new(user)

      events.each do |event|
        begin
          calendar     = event.google_calendar
          user_service = service.send(:user_calendar_service)
          user_service.delete_event(calendar.google_calendar_id, event.google_event_id)
          event.destroy
          deleted_count += 1
          print "."
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            event.destroy
            deleted_count += 1
            print "x"
          else
            error_count += 1
            print "E"
          end
        rescue => e
          error_count += 1
          print "E"
          Rails.logger.error "Failed to delete orphaned event #{event.id}: #{e.message}"
        end
      end
      puts
    end

    puts "\n=== Cleanup Complete ==="
    puts "Deleted: #{deleted_count} events"
    puts "Errors:  #{error_count}"
  end
end
