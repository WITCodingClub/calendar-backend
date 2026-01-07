# frozen_string_literal: true

namespace :cleanup do
  desc "Remove duplicate TBD events from Google Calendar when valid location events exist"
  task duplicate_tbd_events: :environment do
    puts "Starting cleanup of duplicate TBD events..."
    
    if ENV['USER_ID'].present?
      user = User.find(ENV['USER_ID'])
      puts "Cleaning up duplicate events for user #{user.id} (#{user.email})"
      CleanupDuplicateTbdEventsJob.perform_now(user.id)
    else
      puts "Cleaning up duplicate events for all users..."
      CleanupDuplicateTbdEventsJob.perform_now
    end
    
    puts "Cleanup complete!"
  end
  
  desc "Dry run - show what duplicate TBD events would be deleted"
  task duplicate_tbd_events_dry_run: :environment do
    puts "DRY RUN: Checking for duplicate TBD events..."
    
    users = if ENV['USER_ID'].present?
              [User.find(ENV['USER_ID'])]
            else
              User.joins(google_credential: :google_calendar)
            end
    
    total_duplicates = 0
    
    users.find_each do |user|
      google_calendar = user.google_credential&.google_calendar
      next unless google_calendar

      google_events = google_calendar.google_calendar_events
                                     .where.not(meeting_time_id: nil)
                                     .includes(meeting_time: [:building, :room, :course])

      grouped_events = google_events.group_by do |event|
        mt = event.meeting_time
        next unless mt
        
        [
          mt.course_id,
          mt.day_of_week,
          mt.begin_time,
          mt.end_time,
          mt.start_date,
          mt.end_date
        ]
      end

      user_duplicates = 0

      grouped_events.each do |key, events|
        next if events.size <= 1
        
        tbd_events = []
        valid_events = []
        
        events.each do |event|
          mt = event.meeting_time
          building = mt.building
          room = mt.room
          
          is_tbd = (building && (building.name&.downcase&.include?("to be determined") || 
                                 building.name&.downcase&.include?("tbd") || 
                                 building.abbreviation&.downcase == "tbd")) ||
                   (room && (room.number&.downcase == "tbd" || room.number == "000"))
          
          if is_tbd
            tbd_events << event
          else
            valid_events << event
          end
        end
        
        if valid_events.any? && tbd_events.any?
          user_duplicates += tbd_events.size
          course = events.first.meeting_time.course
          puts "  User #{user.id}: Course #{course.subject}-#{course.course_number} has #{tbd_events.size} TBD duplicate(s)"
        end
      end
      
      if user_duplicates > 0
        puts "User #{user.id} (#{user.email}) has #{user_duplicates} duplicate TBD events"
        total_duplicates += user_duplicates
      end
    end
    
    puts "\nTotal duplicate TBD events found: #{total_duplicates}"
    puts "Run 'rails cleanup:duplicate_tbd_events' to delete these duplicates"
  end
end