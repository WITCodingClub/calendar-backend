# frozen_string_literal: true

namespace :calendar do
  desc "Delete duplicate events with 'To Be Determined 000' location for all users"
  task cleanup_tbd_duplicates: :environment do
    puts "Cleaning up duplicate events with 'To Be Determined 000' location..."
    puts "=" * 60
    
    total_users_processed = 0
    total_events_deleted = 0
    users_with_bad_events = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 20) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        begin
          puts "Processing user #{user.id} (#{user.email})..."
          total_users_processed += 1
          
          service = GoogleCalendarService.new(user)
          service_account_service = service.send(:service_account_calendar_service)
          
          # Get all events from this user's calendar
          all_events = service_account_service.list_events(
            calendar.google_calendar_id,
            max_results: 1000,
            single_events: true
          )
          
          # Filter events with the problematic location
          bad_events = all_events.items.select do |event|
            event.location == "To Be Determined 000"
          end
          
          if bad_events.any?
            users_with_bad_events += 1
            puts "  Found #{bad_events.size} events with 'To Be Determined 000' location"
            
            # Show sample for verification
            sample_event = bad_events.first
            start_time = sample_event.start&.date_time || sample_event.start&.date
            puts "  Sample: '#{sample_event.summary}' at #{start_time}"
            
            deleted_count = 0
            
            bad_events.each do |event|
              begin
                service_account_service.delete_event(calendar.google_calendar_id, event.id)
                deleted_count += 1
                print "."
              rescue Google::Apis::ClientError => e
                if e.status_code == 404
                  # Event already deleted
                  print "x"
                else
                  print "E"
                  Rails.logger.error "Failed to delete event #{event.id}: #{e.message}"
                end
              rescue => e
                print "E"
                Rails.logger.error "Failed to delete event #{event.id}: #{e.message}"
              end
            end
            
            puts # New line after progress dots
            puts "  ✅ Deleted #{deleted_count}/#{bad_events.size} events"
            total_events_deleted += deleted_count
            
            # Also clean up any orphaned database records
            orphaned_db_events = calendar.google_calendar_events
                                         .where("location = ?", "To Be Determined 000")
            
            if orphaned_db_events.any?
              puts "  Cleaning up #{orphaned_db_events.count} orphaned database records"
              orphaned_db_events.destroy_all
            end
          else
            puts "  No problematic events found"
          end
          
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            puts "  Calendar not found - cleaning up stale database record"
            calendar.delete
          else
            puts "  Error accessing calendar: #{e.message}"
          end
        rescue => e
          puts "  Error processing user: #{e.message}"
        end
        
        # Small delay to avoid rate limits
        sleep(0.5)
      end
    end
    
    puts "\n=== Cleanup Complete ==="
    puts "Users processed: #{total_users_processed}"
    puts "Users with problematic events: #{users_with_bad_events}"
    puts "Total events deleted: #{total_events_deleted}"
    
    if total_events_deleted > 0
      puts "\n✅ Successfully cleaned up duplicate events with 'To Be Determined 000' location"
      puts "Users should no longer see duplicate events in their calendars"
    else
      puts "\nNo problematic events found across all users"
    end
  end
  
  desc "Check how many users have duplicate TBD events (dry run)"
  task check_tbd_duplicates: :environment do
    puts "Checking for events with 'To Be Determined 000' location (dry run)..."
    puts "=" * 60
    
    total_users_checked = 0
    users_with_bad_events = 0
    total_bad_events = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 20) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        begin
          total_users_checked += 1
          
          service = GoogleCalendarService.new(user)
          service_account_service = service.send(:service_account_calendar_service)
          
          # Get all events from this user's calendar
          all_events = service_account_service.list_events(
            calendar.google_calendar_id,
            max_results: 1000,
            single_events: true
          )
          
          # Filter events with the problematic location
          bad_events = all_events.items.select do |event|
            event.location == "To Be Determined 000"
          end
          
          if bad_events.any?
            users_with_bad_events += 1
            total_bad_events += bad_events.size
            
            puts "User #{user.id} (#{user.email}): #{bad_events.size} problematic events"
            
            # Show sample event details
            sample = bad_events.first
            start_time = sample.start&.date_time || sample.start&.date
            puts "  Sample: '#{sample.summary}' at #{start_time}"
            
            # Check for recurrence ending on the 9th
            recurrence_info = sample.recurrence&.first
            if recurrence_info&.include?("20260109")
              puts "  ✓ Confirms recurrence ending Jan 9th"
            end
          else
            print "."
          end
          
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            puts "\nUser #{user.id}: Calendar not found"
          else
            puts "\nUser #{user.id}: Error - #{e.message}"
          end
        rescue => e
          puts "\nUser #{user.id}: Error - #{e.message}"
        end
      end
    end
    
    puts "\n\n=== Summary ==="
    puts "Users checked: #{total_users_checked}"
    puts "Users with problematic events: #{users_with_bad_events}"
    puts "Total problematic events: #{total_bad_events}"
    
    if users_with_bad_events > 0
      puts "\nRun 'rake calendar:cleanup_tbd_duplicates' to remove these events"
    else
      puts "\nNo problematic events found!"
    end
  end
end