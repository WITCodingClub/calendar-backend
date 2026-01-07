# frozen_string_literal: true

namespace :calendar do
  desc "Find and optionally clean up orphaned Google Calendar events"
  task find_orphaned_events: :environment do
    puts "Searching for orphaned Google Calendar events..."
    puts "=" * 60
    
    orphaned_events = {
      missing_meeting_times: [],
      missing_final_exams: [],
      missing_university_events: [],
      unenrolled_courses: [],
      past_events: []
    }
    
    GoogleCalendarEvent.includes(:meeting_time, :final_exam, :university_calendar_event, google_calendar: :user).find_each do |event|
      user = event.user
      
      # Check for missing associations
      if event.meeting_time_id.present? && event.meeting_time.nil?
        orphaned_events[:missing_meeting_times] << event
        puts "Event #{event.id}: Missing meeting_time #{event.meeting_time_id} for user #{user&.id}"
      elsif event.final_exam_id.present? && event.final_exam.nil?
        orphaned_events[:missing_final_exams] << event
        puts "Event #{event.id}: Missing final_exam #{event.final_exam_id} for user #{user&.id}"
      elsif event.university_calendar_event_id.present? && event.university_calendar_event.nil?
        orphaned_events[:missing_university_events] << event
        puts "Event #{event.id}: Missing university_event #{event.university_calendar_event_id} for user #{user&.id}"
      end
      
      # Check if user is still enrolled in the course
      if event.meeting_time_id.present? && event.meeting_time.present?
        course = event.meeting_time.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned_events[:unenrolled_courses] << event
          puts "Event #{event.id}: User #{user.id} no longer enrolled in #{course.title}"
        end
      elsif event.final_exam_id.present? && event.final_exam.present?
        course = event.final_exam.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned_events[:unenrolled_courses] << event
          puts "Event #{event.id}: User #{user.id} no longer enrolled in final exam course #{course.title}"
        end
      end
      
      # Check for very old events (ended over 6 months ago)
      if event.end_time && event.end_time < 6.months.ago
        orphaned_events[:past_events] << event
      end
    end
    
    puts "\n=== Orphaned Events Summary ==="
    puts "Missing meeting times: #{orphaned_events[:missing_meeting_times].size}"
    puts "Missing final exams: #{orphaned_events[:missing_final_exams].size}"
    puts "Missing university events: #{orphaned_events[:missing_university_events].size}"
    puts "Unenrolled courses: #{orphaned_events[:unenrolled_courses].size}"
    puts "Old events (>6 months): #{orphaned_events[:past_events].size}"
    
    total_orphaned = orphaned_events.values.flatten.uniq.size
    puts "\nTotal unique orphaned events: #{total_orphaned}"
    
    if total_orphaned > 0
      puts "\nRun 'rake calendar:clean_orphaned_events' to remove these events"
    end
  end
  
  desc "Clean up orphaned Google Calendar events"
  task clean_orphaned_events: :environment do
    puts "Cleaning up orphaned Google Calendar events..."
    puts "=" * 60
    
    deleted_count = 0
    error_count = 0
    
    # Find orphaned events
    orphaned_events = []
    
    GoogleCalendarEvent.includes(:meeting_time, :final_exam, :university_calendar_event, google_calendar: :user).find_each do |event|
      user = event.user
      
      # Missing associations
      if (event.meeting_time_id.present? && event.meeting_time.nil?) ||
         (event.final_exam_id.present? && event.final_exam.nil?) ||
         (event.university_calendar_event_id.present? && event.university_calendar_event.nil?)
        orphaned_events << event
        next
      end
      
      # Unenrolled courses
      if event.meeting_time_id.present? && event.meeting_time.present?
        course = event.meeting_time.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned_events << event
        end
      elsif event.final_exam_id.present? && event.final_exam.present?
        course = event.final_exam.course
        if course && user && !user.enrollments.exists?(course_id: course.id)
          orphaned_events << event
        end
      end
    end
    
    # Group by user for efficient deletion
    events_by_user = orphaned_events.group_by(&:user)
    
    events_by_user.each do |user, events|
      next unless user
      
      puts "Processing #{events.size} orphaned events for user #{user.id} (#{user.email})..."
      
      service = GoogleCalendarService.new(user)
      
      events.each do |event|
        begin
          calendar = event.google_calendar
          
          # Delete from Google Calendar
          user_service = service.send(:user_calendar_service)
          user_service.delete_event(
            calendar.google_calendar_id,
            event.google_event_id
          )
          
          # Delete from database
          event.destroy
          deleted_count += 1
          print "."
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            # Event doesn't exist in Google Calendar, just remove from DB
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
      puts # New line after progress dots
    end
    
    puts "\n=== Cleanup Complete ==="
    puts "Deleted: #{deleted_count} events"
    puts "Errors: #{error_count}"
  end
  
  desc "Find events that exist in Google Calendar but not in database"
  task find_untracked_events: :environment do
    puts "Searching for untracked Google Calendar events..."
    puts "This will check each user's calendar for events not in the database"
    puts "=" * 60
    
    untracked_count = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 10) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        begin
          service = GoogleCalendarService.new(user)
          gcal_service = service.send(:user_calendar_service)
          
          # Get all events from Google Calendar
          gcal_events = gcal_service.list_events(
            calendar.google_calendar_id,
            single_events: true,
            order_by: 'startTime',
            time_min: 1.month.ago.iso8601,
            time_max: 6.months.from_now.iso8601
          )
          
          # Get all tracked event IDs for this calendar
          tracked_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set
          
          # Find untracked events
          untracked = gcal_events.items.reject { |e| tracked_ids.include?(e.id) }
          
          if untracked.any?
            puts "\nUser #{user.id} (#{user.email}) has #{untracked.size} untracked events:"
            untracked.first(5).each do |event|
              puts "  - #{event.summary} at #{event.location} (ID: #{event.id})"
            end
            untracked_count += untracked.size
          end
        rescue => e
          puts "Error checking user #{user.id}: #{e.message}"
        end
      end
    end
    
    puts "\n=== Summary ==="
    puts "Total untracked events: #{untracked_count}"
  end
end