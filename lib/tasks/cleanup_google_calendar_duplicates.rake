# frozen_string_literal: true

namespace :calendar do
  desc "Find and clean duplicate events in Google Calendar that aren't tracked in database"
  task cleanup_google_duplicates: :environment do
    puts "Finding duplicate events in Google Calendar..."
    puts "This will remove events from Google Calendar that aren't tracked in the database"
    puts "=" * 60
    
    total_deleted = 0
    total_errors = 0
    
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
            single_events: true,  # Expand recurring events
            order_by: 'startTime',
            time_min: 3.months.ago.iso8601,
            time_max: 6.months.from_now.iso8601,
            max_results: 2500
          )
          
          # Get all tracked event IDs for this calendar
          tracked_event_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set
          
          # Group Google Calendar events by summary + location + start time to find duplicates
          event_groups = {}
          gcal_events.items.each do |event|
            # Skip if this event is tracked in our database
            next if tracked_event_ids.include?(event.id)
            
            # Create a key based on event properties
            start_time = event.start&.date_time || event.start&.date
            key = "#{event.summary}|#{event.location}|#{start_time}"
            
            event_groups[key] ||= []
            event_groups[key] << event
          end
          
          # Find groups with duplicates
          duplicate_groups = event_groups.select { |_, events| events.size > 0 }
          
          if duplicate_groups.any?
            puts "\nUser #{user.id} (#{user.email}) has untracked events:"
            puts "  Found #{duplicate_groups.values.flatten.size} untracked events in #{duplicate_groups.size} groups"
            
            # Delete all untracked events
            duplicate_groups.each do |key, events|
              summary, location, _ = key.split("|")
              puts "  Deleting #{events.size} untracked: '#{summary}' at '#{location}'"
              
              events.each do |event|
                begin
                  gcal_service.delete_event(calendar.google_calendar_id, event.id)
                  total_deleted += 1
                  print "."
                rescue Google::Apis::ClientError => e
                  if e.status_code == 404
                    # Already deleted
                    print "x"
                  else
                    total_errors += 1
                    print "E"
                  end
                rescue => e
                  total_errors += 1
                  print "E"
                  Rails.logger.error "Failed to delete event: #{e.message}"
                end
              end
              puts # New line
            end
          end
        rescue => e
          puts "Error processing user #{user.id}: #{e.message}"
        end
      end
    end
    
    puts "\n=== Cleanup Complete ==="
    puts "Deleted: #{total_deleted} untracked events from Google Calendar"
    puts "Errors: #{total_errors}"
    puts "\nRun 'rake calendar:force_resync_all' to ensure all calendars are up to date"
  end
  
  desc "Dry run - show what duplicate events would be deleted"
  task check_google_duplicates: :environment do
    puts "Checking for untracked events in Google Calendar (dry run)..."
    puts "=" * 60
    
    total_untracked = 0
    affected_users = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 10) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        begin
          service = GoogleCalendarService.new(user)
          gcal_service = service.send(:user_calendar_service)
          
          # Get events from Google Calendar
          gcal_events = gcal_service.list_events(
            calendar.google_calendar_id,
            single_events: true,
            order_by: 'startTime',
            time_min: 3.months.ago.iso8601,
            time_max: 6.months.from_now.iso8601,
            max_results: 2500
          )
          
          # Get tracked event IDs
          tracked_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set
          db_events = calendar.google_calendar_events.includes(:meeting_time, :final_exam)
          
          # Find untracked events
          untracked = gcal_events.items.reject { |e| tracked_ids.include?(e.id) }
          
          if untracked.any?
            affected_users += 1
            total_untracked += untracked.size
            
            puts "\nUser #{user.id} (#{user.email}):"
            puts "  Database events: #{db_events.count}"
            puts "  Google Calendar events: #{gcal_events.items.size}"
            puts "  Untracked events: #{untracked.size}"
            
            # Show examples
            puts "  Examples of untracked events:"
            untracked.first(3).each do |event|
              start_time = event.start&.date_time || event.start&.date
              puts "    - '#{event.summary}' at '#{event.location}' (#{start_time})"
              
              # Try to find a matching tracked event
              matching = db_events.find do |db_event|
                db_event.summary == event.summary && 
                db_event.location == event.location
              end
              
              if matching
                puts "      ^ Possible duplicate of tracked event ID #{matching.id}"
              end
            end
          end
        rescue => e
          puts "Error checking user #{user.id}: #{e.message}"
        end
      end
    end
    
    puts "\n=== Summary ==="
    puts "Affected users: #{affected_users}"
    puts "Total untracked events in Google Calendar: #{total_untracked}"
    puts "\nRun 'rake calendar:cleanup_google_duplicates' to remove these untracked events"
  end
  
  desc "Force resync all user calendars"
  task force_resync_all: :environment do
    puts "Queueing calendar resync for all users..."
    
    count = 0
    User.joins(:enrollments).distinct.find_each do |user|
      if user.google_credential&.google_calendar
        GoogleCalendarSyncJob.perform_later(user, force: true)
        count += 1
        print "."
      end
    end
    
    puts "\nQueued #{count} sync jobs"
  end
end