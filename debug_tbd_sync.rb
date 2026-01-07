#!/usr/bin/env ruby
# Debug script to trace TBD sync logic

puts 'Debugging ACTUAL sync flow for TBD meeting times...'

user = User.first
mt = MeetingTime.joins(:building).where('buildings.name ILIKE ?', '%to be determined%').first
course = mt.course

puts "Testing meeting time #{mt.id} from course #{course.title}"
puts "Building: '#{mt.building.name}'"
puts "Room: #{mt.room&.number}"

enrollment = Enrollment.find_by(user: user, course: course)
puts "User enrolled: #{!!enrollment}"

if enrollment
  puts "Day of week: #{mt.day_of_week}"
  
  if mt.day_of_week.present?
    first_meeting_date = user.send(:find_first_meeting_date, mt)
    puts "First meeting date: #{first_meeting_date}"
    
    if first_meeting_date
      start_time = user.send(:parse_time, first_meeting_date, mt.begin_time)
      end_time = user.send(:parse_time, first_meeting_date, mt.end_time)
      puts "Times: #{start_time} - #{end_time}"
      
      if start_time && end_time
        puts "\n--- TBD CHECKS ---"
        
        building_tbd = mt.building && user.send(:tbd_building?, mt.building)
        room_tbd = mt.room && user.send(:tbd_room?, mt.room) 
        location_tbd = mt.room && mt.building && user.send(:tbd_location?, mt.building, mt.room)
        
        puts "Building TBD check: #{building_tbd}"
        puts "Room TBD check: #{room_tbd}"
        puts "Location TBD check: #{location_tbd}"
        
        should_skip = building_tbd || room_tbd || location_tbd
        puts "SHOULD SKIP: #{should_skip}"
        
        if should_skip
          puts "✅ This meeting time should be SKIPPED"
        else
          puts "❌ This meeting time would CREATE AN EVENT"
          
          location = if mt.room && mt.building
                       "#{mt.building.name} - #{mt.room.formatted_number}"
                     elsif mt.room
                       mt.room.formatted_number
                     end
          puts "Location that would be created: '#{location}'"
        end
      end
    end
  end
end