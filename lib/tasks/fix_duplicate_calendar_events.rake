# frozen_string_literal: true

namespace :calendar do
  desc "Fix duplicate Google Calendar events and TBD locations"
  task fix_duplicates: :environment do
    puts "Starting duplicate calendar event cleanup..."
    
    fixed_users = 0
    total_duplicates_removed = 0
    total_events_fixed = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 50) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        puts "Processing user #{user.id} (#{user.email})..."
        
        # Use the same duplicate detection logic from GoogleCalendarService
        all_existing_events = calendar.google_calendar_events.to_a
        existing_events = {}
        duplicates_to_delete = []

        all_existing_events.each do |e|
          event_key = if e.meeting_time_id
                        "mt_#{e.meeting_time_id}"
                      elsif e.final_exam_id
                        "fe_#{e.final_exam_id}"
                      else
                        "ue_#{e.university_calendar_event_id}"
                      end

          if existing_events[event_key]
            # Keep the newer one, mark old one for deletion
            if e.created_at > existing_events[event_key].created_at
              duplicates_to_delete << existing_events[event_key]
              existing_events[event_key] = e
            else
              duplicates_to_delete << e
            end
          else
            existing_events[event_key] = e
          end
        end

        if duplicates_to_delete.any?
          puts "  Found #{duplicates_to_delete.size} duplicate events to remove"
          fixed_users += 1
          
          # Delete from Google Calendar and database
          service = GoogleCalendarService.new(user)
          duplicates_to_delete.each do |cal_event|
            begin
              # Get the service instances
              user_service = service.send(:user_calendar_service)
              
              # Delete from Google Calendar
              user_service.delete_event(
                calendar.google_calendar_id,
                cal_event.google_event_id
              )
              
              # Delete from database
              cal_event.destroy
              total_duplicates_removed += 1
              
              print "."
            rescue Google::Apis::ClientError => e
              if e.status_code == 404
                # Event doesn't exist in Google Calendar, just remove from DB
                cal_event.destroy
                total_duplicates_removed += 1
                print "x"
              else
                puts "\n  Error deleting event #{cal_event.id}: #{e.message}"
              end
            rescue => e
              puts "\n  Error deleting event #{cal_event.id}: #{e.message}"
            end
          end
          puts # New line after dots
        end
        
        # Now force a resync to fix any TBD locations
        if user.enrollments.any?
          begin
            puts "  Triggering calendar resync..."
            GoogleCalendarSyncJob.perform_later(user, force: true)
            total_events_fixed += all_existing_events.size
          rescue => e
            puts "  Error queueing sync job: #{e.message}"
          end
        end
      end
    end
    
    puts "\n=== Cleanup Complete ==="
    puts "Users fixed: #{fixed_users}"
    puts "Duplicate events removed: #{total_duplicates_removed}"
    puts "Calendar syncs queued: #{fixed_users}"
    puts "\nThe calendar sync jobs will run in the background to fix TBD locations."
  end
  
  desc "Dry run to check for duplicate events"
  task check_duplicates: :environment do
    puts "Checking for duplicate calendar events..."
    
    users_with_duplicates = 0
    total_duplicates = 0
    tbd_locations = 0
    
    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 50) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar
        
        # Check for duplicates
        duplicates = calendar.google_calendar_events
                            .where.not(meeting_time_id: nil)
                            .group(:meeting_time_id)
                            .having('count(*) > 1')
                            .count
        
        if duplicates.any?
          users_with_duplicates += 1
          user_total = duplicates.values.sum - duplicates.size # Extra events beyond the first
          total_duplicates += user_total
          puts "User #{user.id}: #{user_total} duplicate events across #{duplicates.size} meeting times"
        end
        
        # Check for TBD locations
        tbd_count = calendar.google_calendar_events.where("location ILIKE ?", "%TBD%").count
        if tbd_count > 0
          tbd_locations += tbd_count
          puts "User #{user.id}: #{tbd_count} events with TBD locations"
        end
      end
    end
    
    puts "\n=== Summary ==="
    puts "Users with duplicates: #{users_with_duplicates}"
    puts "Total duplicate events: #{total_duplicates}"
    puts "Total TBD locations: #{tbd_locations}"
  end
end