# frozen_string_literal: true

# One-time cleanup task to fix location display issues caused by TBD/empty building records.
# This task should be run after deploying the tbd_building? fix to clean up existing data.
#
# TBD locations can appear as:
# - Empty/null building name or abbreviation
# - Building name containing "to be determined" or "tbd"
# - Building abbreviation == "TBD"
# - Room number == 0

namespace :cleanup do
  # Helper to check if a building is TBD (matches CourseScheduleSyncable#tbd_building?)
  def tbd_building?(building)
    return false unless building

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  def tbd_room?(room)
    return false unless room
    room.number == 0
  end

  def tbd_location?(mt)
    tbd_building?(mt.building) || tbd_room?(mt.room)
  end

  desc "Diagnose TBD building issues - show what would be cleaned up (dry run)"
  task diagnose_tbd_duplicates: :environment do
    puts "Diagnosing TBD location duplicates..."
    puts "=" * 60

    # Find all TBD buildings
    tbd_buildings = Building.all.select { |b| tbd_building?(b) }
    puts "\nTBD buildings found: #{tbd_buildings.count}"
    tbd_buildings.each do |b|
      meeting_time_count = MeetingTime.joins(:room).where(rooms: { building_id: b.id }).count
      puts "  Building ID #{b.id}: name='#{b.name}' abbr='#{b.abbreviation}' - #{meeting_time_count} meeting times"
    end

    # Find courses that have both TBD and valid location meeting times
    puts "\nCourses with both TBD and valid locations (duplicates to clean):"

    duplicates_found = 0
    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }

      grouped.each do |(day, begin_t, end_t), mts|
        next if mts.size <= 1

        tbd_mts = mts.select { |mt| tbd_location?(mt) }
        valid_mts = mts.reject { |mt| tbd_location?(mt) }

        if tbd_mts.any? && valid_mts.any?
          duplicates_found += 1
          puts "  Course: #{course.crn} - #{course.title}"
          puts "    Day: #{day}, Time: #{begin_t}-#{end_t}"
          puts "    TBD MeetingTimes: #{tbd_mts.map(&:id).join(', ')}"
          tbd_mts.each do |mt|
            puts "      -> '#{mt.building&.name}'/#{mt.building&.abbreviation}' Room=#{mt.room&.number}"
          end
          puts "    Valid MeetingTimes: #{valid_mts.map(&:id).join(', ')}"
          valid_mts.each do |mt|
            puts "      -> #{mt.building.abbreviation} #{mt.room.number}"
          end
        end
      end
    end

    puts "\nTotal duplicate groups found: #{duplicates_found}"
    puts "\n" + "=" * 60
    puts "Run 'rails cleanup:fix_tbd_duplicates' to remove duplicate TBD MeetingTimes"
    puts "Then run 'rails cleanup:sync_affected_users' to update their calendars"
  end

  # Keep old task name as alias
  desc "Diagnose empty building issues (alias for diagnose_tbd_duplicates)"
  task diagnose_empty_buildings: :diagnose_tbd_duplicates

  desc "Remove duplicate MeetingTimes where valid location exists alongside TBD version"
  task fix_tbd_duplicates: :environment do
    puts "Fixing TBD location duplicates..."

    deleted_count = 0
    events_deleted = 0

    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }

      grouped.each do |(day, begin_t, end_t), mts|
        next if mts.size <= 1

        tbd_mts = mts.select { |mt| tbd_location?(mt) }
        valid_mts = mts.reject { |mt| tbd_location?(mt) }

        # Only delete TBD MTs if we have a valid one to keep
        if tbd_mts.any? && valid_mts.any?
          tbd_mts.each do |mt|
            # Count associated calendar events that will be deleted
            events_deleted += mt.google_calendar_events.count

            puts "  Deleting MeetingTime #{mt.id} for course #{course.crn} (TBD location, valid location exists)"
            mt.destroy!
            deleted_count += 1
          end
        end
      end
    end

    puts "\nDeleted #{deleted_count} duplicate TBD MeetingTimes"
    puts "Deleted #{events_deleted} associated GoogleCalendarEvents (they'll be recreated on next sync)"
    puts "\nRun 'rails cleanup:sync_affected_users' to update affected user calendars"
  end

  # Keep old task name as alias
  desc "Remove duplicate MeetingTimes (alias for fix_tbd_duplicates)"
  task fix_empty_building_duplicates: :fix_tbd_duplicates

  desc "Trigger calendar sync for all users (will apply fixed TBD detection)"
  task sync_affected_users: :environment do
    puts "Queueing calendar syncs for all users with Google Calendars..."

    users = User.joins(:google_calendars).distinct
    count = 0

    users.find_each do |user|
      GoogleCalendarSyncJob.perform_later(user, force: true)
      count += 1
      print "." if count % 10 == 0
    end

    puts "\nQueued #{count} calendar syncs"
    puts "Monitor job queue to see progress"
  end

  desc "Run CleanupDuplicateTbdEventsJob to remove TBD duplicates from Google Calendars"
  task cleanup_tbd_calendar_events: :environment do
    puts "Running CleanupDuplicateTbdEventsJob for all users..."
    puts "This will now correctly detect empty-building events as TBD and remove duplicates."

    CleanupDuplicateTbdEventsJob.perform_now

    puts "Done. Check logs for details on deleted events."
  end

  desc "Full cleanup: diagnose, fix duplicates, and sync (interactive)"
  task full_empty_building_cleanup: :environment do
    puts "=" * 60
    puts "FULL EMPTY BUILDING CLEANUP"
    puts "=" * 60
    puts "\nStep 1: Diagnosing issues..."
    Rake::Task["cleanup:diagnose_empty_buildings"].invoke

    print "\nProceed with fixing duplicate MeetingTimes? (y/n): "
    if STDIN.gets.chomp.downcase == "y"
      puts "\nStep 2: Fixing duplicate MeetingTimes..."
      Rake::Task["cleanup:fix_empty_building_duplicates"].invoke

      print "\nProceed with calendar sync for all users? (y/n): "
      if STDIN.gets.chomp.downcase == "y"
        puts "\nStep 3: Syncing affected calendars..."
        Rake::Task["cleanup:sync_affected_users"].invoke

        print "\nRun TBD cleanup job on Google Calendars? (y/n): "
        if STDIN.gets.chomp.downcase == "y"
          puts "\nStep 4: Cleaning up TBD duplicates in Google Calendars..."
          Rake::Task["cleanup:cleanup_tbd_calendar_events"].invoke
        end
      end
    end

    puts "\nCleanup complete!"
  end
end
