# frozen_string_literal: true

namespace :calendar do
  desc "Find and clean up ALL duplicate events in Google Calendar (not just TBD)"
  task cleanup_all_duplicates: :environment do
    puts "Finding and cleaning up ALL duplicate events in Google Calendar..."
    puts "=" * 70
    
    total_users_processed = 0
    total_events_deleted = 0
    users_with_duplicates = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 10) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        begin
          puts "Processing user #{user.id} (#{user.email})..."
          total_users_processed += 1
          
          service = GoogleCalendarService.new(user)
          service_account_service = service.send(:service_account_calendar_service)
          
          # Get all events from Google Calendar
          all_google_events = service_account_service.list_events(
            calendar.google_calendar_id,
            max_results: 1000,
            single_events: true,
            time_min: 1.month.ago.iso8601,
            time_max: 6.months.from_now.iso8601
          )
          
          # Group events by summary + start time to find duplicates
          event_groups = {}
          all_google_events.items.each do |event|
            start_time = event.start&.date_time || event.start&.date
            next unless start_time && event.summary
            
            # Create key: summary + start time (to find exact duplicates)
            key = "#{event.summary.strip}|#{start_time}"
            event_groups[key] ||= []
            event_groups[key] << event
          end
          
          # Find groups with duplicates (more than 1 event)
          duplicate_groups = event_groups.select { |_, events| events.size > 1 }
          
          if duplicate_groups.any?
            users_with_duplicates += 1
            total_duplicates = duplicate_groups.values.map(&:size).sum - duplicate_groups.size
            puts "  Found #{duplicate_groups.size} event groups with duplicates (#{total_duplicates} extra events)"
            
            duplicate_groups.each do |key, events|
              summary, start_time = key.split("|", 2)
              puts "    '#{summary}' at #{start_time}: #{events.size} copies"
              
              # Keep the first event, delete the rest
              events_to_delete = events[1..-1]
              deleted_count = 0
              
              events_to_delete.each do |event|
                begin
                  service_account_service.delete_event(calendar.google_calendar_id, event.id)
                  deleted_count += 1
                  total_events_deleted += 1
                  print "."
                rescue Google::Apis::ClientError => e
                  if e.status_code == 404
                    # Already deleted
                    print "x"
                  else
                    print "E"
                    Rails.logger.error "Failed to delete duplicate event: #{e.message}"
                  end
                rescue => e
                  print "E"
                  Rails.logger.error "Failed to delete duplicate event: #{e.message}"
                end
              end
              
              puts " (deleted #{deleted_count}/#{events_to_delete.size} duplicates)"
            end
            
            # Clean up any orphaned database records
            puts "  Cleaning up orphaned database records..."
            orphaned_count = 0
            
            calendar.google_calendar_events.find_each do |db_event|
              # Check if this event still exists in Google Calendar
              begin
                service_account_service.get_event(calendar.google_calendar_id, db_event.google_event_id)
              rescue Google::Apis::ClientError => e
                if e.status_code == 404
                  # Event was deleted from Google Calendar, remove from database
                  db_event.destroy
                  orphaned_count += 1
                end
              end
            end
            
            puts "  Removed #{orphaned_count} orphaned database records" if orphaned_count > 0
          else
            puts "  No duplicates found"
          end
          
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            puts "  Calendar not found - cleaning up stale database record"
            calendar.delete
          else
            puts "  Error: #{e.message}"
          end
        rescue => e
          puts "  Error: #{e.message}"
        end
        
        # Small delay to be nice to the API
        sleep(0.5)
      end
    end
    
    puts "\n=== Cleanup Summary ==="
    puts "Users processed: #{total_users_processed}"
    puts "Users with duplicates: #{users_with_duplicates}" 
    puts "Total duplicate events deleted: #{total_events_deleted}"
    
    if total_events_deleted > 0
      puts "\n✅ Successfully cleaned up duplicate events!"
      puts "Users should refresh their calendars to see the changes."
    else
      puts "\nNo duplicate events found."
    end
  end
  
  desc "Check for ALL duplicate events (dry run)"
  task check_all_duplicates: :environment do
    puts "Checking for ALL duplicate events (dry run)..."
    puts "=" * 60
    
    total_users_checked = 0
    users_with_duplicates = 0
    total_duplicates = 0
    
    User.joins(oauth_credentials: :google_calendar).limit(5).find_each do |user|
      calendar = user.google_credential&.google_calendar
      next unless calendar
      
      begin
        total_users_checked += 1
        puts "Checking user #{user.id} (#{user.email})..."
        
        service = GoogleCalendarService.new(user)
        service_account_service = service.send(:service_account_calendar_service)
        
        # Get events for the next few weeks
        all_events = service_account_service.list_events(
          calendar.google_calendar_id,
          max_results: 500,
          single_events: true,
          time_min: Time.zone.today.iso8601,
          time_max: 1.month.from_now.iso8601
        )
        
        # Group by summary + start time
        event_groups = {}
        all_events.items.each do |event|
          start_time = event.start&.date_time || event.start&.date
          next unless start_time && event.summary
          
          key = "#{event.summary.strip}|#{start_time}"
          event_groups[key] ||= []
          event_groups[key] << event
        end
        
        duplicates = event_groups.select { |_, events| events.size > 1 }
        
        if duplicates.any?
          users_with_duplicates += 1
          user_total = duplicates.values.map(&:size).sum - duplicates.size
          total_duplicates += user_total
          
          puts "  #{duplicates.size} event groups with duplicates (#{user_total} extra events):"
          duplicates.each do |key, events|
            summary, start_time = key.split("|", 2)
            puts "    '#{summary}' at #{start_time[0..18]}... (#{events.size} copies)"
          end
        else
          puts "  No duplicates found"
        end
        
      rescue => e
        puts "  Error: #{e.message}"
      end
    end
    
    puts "\n=== Summary ==="
    puts "Users checked: #{total_users_checked}"
    puts "Users with duplicates: #{users_with_duplicates}"
    puts "Total duplicate events: #{total_duplicates}"
    
    if users_with_duplicates > 0
      puts "\nRun 'rake calendar:cleanup_all_duplicates' to remove duplicates"
    end
  end
end