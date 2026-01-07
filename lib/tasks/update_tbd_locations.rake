namespace :courses do
  desc "Update location data for courses with TBD/room 0 locations by re-fetching from LeopardWeb"
  task update_tbd_locations: :environment do
    puts "Finding courses with TBD or room 0 locations..."
    
    # Room IDs that represent TBD/unknown locations (room 0 or TBD building)
    tbd_room_ids = [59, 75, 150, 151, 152, 156, 160, 162] # room number 0 + TBD building room
    
    # Find courses using these TBD rooms that have meeting times
    courses_with_tbd = Course.joins(:meeting_times)
                            .where(meeting_times: {room_id: tbd_room_ids})
                            .distinct
                            .includes(:term, :meeting_times)
    
    puts "Found #{courses_with_tbd.count} courses with TBD locations"
    
    if courses_with_tbd.count == 0
      puts "No courses need location updates!"
      return
    end
    
    puts "\nCourses with TBD locations:"
    courses_with_tbd.each do |course|
      tbd_rooms = course.meeting_times.joins(:room).where(room_id: tbd_room_ids)
      room_info = tbd_rooms.joins(room: :building).pluck("buildings.abbreviation", "rooms.number").map { |b, r| "#{b} #{r}" }.join(", ")
      puts "CRN #{course.crn}: #{course.title} (#{course.term.name}) - Rooms: #{room_info}"
    end
    
    print "\nProceed with updating #{courses_with_tbd.count} courses? This will re-fetch data from LeopardWeb. (y/N): "
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y' || response == 'yes'
      puts "Cancelled."
      return
    end
    
    puts "\nUpdating course locations..."
    updated_count = 0
    failed_count = 0
    skipped_count = 0
    
    courses_with_tbd.each do |course|
      begin
        print "Processing CRN #{course.crn} (#{course.title})... "
        
        # Use LeopardWebService to fetch fresh course data
        detailed_info = LeopardWebService.get_class_details(
          term: course.term.uid,
          course_reference_number: course.crn
        )
        
        if detailed_info.nil? || detailed_info[:meeting_times].blank?
          puts "⚠️  No updated data available"
          skipped_count += 1
          next
        end
        
        # Check if the fetched data has better location info
        has_real_locations = detailed_info[:meeting_times].any? do |mt|
          building = mt[:building]&.strip
          room = mt[:room]&.strip
          building.present? && room.present? && 
            building != "TBD" && room != "0" && room != "TBD"
        end
        
        unless has_real_locations
          puts "⚠️  Still shows TBD in LeopardWeb"
          skipped_count += 1
          next
        end
        
        # Update meeting times with new location data
        MeetingTimesIngestService.call(
          course: course,
          raw_meeting_times: detailed_info[:meeting_times]
        )
        
        puts "✅ Updated successfully"
        updated_count += 1
        
        # Small delay to be respectful to LeopardWeb
        sleep(0.5)
        
      rescue => e
        puts "❌ Failed - #{e.message}"
        Rails.logger.error("Failed to update location for CRN #{course.crn}: #{e.message}")
        failed_count += 1
      end
    end
    
    puts "\n" + "="*60
    puts "SUMMARY:"
    puts "Total courses processed: #{courses_with_tbd.count}"
    puts "Successfully updated: #{updated_count}"
    puts "Skipped (no better data): #{skipped_count}"
    puts "Failed: #{failed_count}"
    puts "="*60
    
    if updated_count > 0
      puts "\n🔄 Consider running a calendar sync for affected users:"
      puts "   rake calendar:sync_all"
    end
  end
end