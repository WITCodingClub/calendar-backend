# frozen_string_literal: true

namespace :cleanup do
  def tbd_building?(building)
    return false unless building

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name.downcase.include?("to be determined") ||
      building.name.downcase.include?("tbd") ||
      building.abbreviation.downcase == "tbd"
  end

  def tbd_room?(room)
    return false unless room
    room.number == 0
  end

  def tbd_location?(mt)
    tbd_building?(mt.room&.building) || tbd_room?(mt.room)
  end

  desc "Diagnose TBD building issues (dry run)"
  task diagnose_tbd_duplicates: :environment do
    puts "Diagnosing TBD location duplicates..."
    puts "=" * 60

    tbd_buildings = Building.all.select { |b| tbd_building?(b) }
    puts "\nTBD buildings found: #{tbd_buildings.count}"
    tbd_buildings.each do |b|
      count = Course::MeetingTime.joins(:room).where(rooms: { building_id: b.id }).count
      puts "  Building #{b.id}: name='#{b.name}' abbr='#{b.abbreviation}' — #{count} meeting times"
    end

    puts "\nCourses with both TBD and valid locations:"

    duplicates_found = 0
    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }

      grouped.each do |(day, begin_t, end_t), mts|
        next if mts.size <= 1

        tbd_mts   = mts.select { |mt| tbd_location?(mt) }
        valid_mts = mts.reject { |mt| tbd_location?(mt) }

        if tbd_mts.any? && valid_mts.any?
          duplicates_found += 1
          puts "  Course #{course.crn} - #{course.title}"
          puts "    Day: #{day}, Time: #{begin_t}-#{end_t}"
          puts "    TBD MeetingTimes: #{tbd_mts.map(&:id).join(', ')}"
          tbd_mts.each { |mt| puts "      -> '#{mt.room&.building&.name}' Room=#{mt.room&.number}" }
          puts "    Valid MeetingTimes: #{valid_mts.map(&:id).join(', ')}"
          valid_mts.each { |mt| puts "      -> #{mt.room&.building&.abbreviation} #{mt.room&.number}" }
        end
      end
    end

    puts "\nTotal duplicate groups found: #{duplicates_found}"
    puts "\nRun 'rails cleanup:fix_tbd_duplicates' to remove duplicate TBD MeetingTimes"
    puts "Then run 'rails cleanup:sync_affected_users' to update their calendars"
  end

  desc "Diagnose empty building issues (alias)"
  task diagnose_empty_buildings: :diagnose_tbd_duplicates

  desc "Remove duplicate MeetingTimes where valid location exists alongside TBD version"
  task fix_tbd_duplicates: :environment do
    puts "Fixing TBD location duplicates..."

    deleted_count = 0
    events_deleted = 0

    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }

      grouped.each do |_, mts|
        next if mts.size <= 1

        tbd_mts   = mts.select { |mt| tbd_location?(mt) }
        valid_mts = mts.reject { |mt| tbd_location?(mt) }

        if tbd_mts.any? && valid_mts.any?
          tbd_mts.each do |mt|
            events_deleted += mt.google_calendar_events.count
            puts "  Deleting MeetingTime #{mt.id} for course #{course.crn} (TBD, valid location exists)"
            mt.destroy!
            deleted_count += 1
          end
        end
      end
    end

    puts "\nDeleted #{deleted_count} duplicate TBD MeetingTimes"
    puts "Deleted #{events_deleted} associated GoogleCalendarEvents (recreated on next sync)"
    puts "\nRun 'rails cleanup:sync_affected_users' to update affected user calendars"
  end

  desc "Remove duplicate MeetingTimes (alias)"
  task fix_empty_building_duplicates: :fix_tbd_duplicates

  desc "Trigger calendar sync for all users with Google Calendars"
  task sync_affected_users: :environment do
    puts "Queueing calendar syncs for all users with Google Calendars..."

    count = 0
    User.joins(:google_calendars).distinct.find_each do |user|
      GoogleCalendarSyncJob.perform_later(user, force: true)
      count += 1
      print "." if count % 10 == 0
    end

    puts "\nQueued #{count} calendar syncs"
  end

  desc "Run CleanupDuplicateTbdEventsJob to remove TBD duplicates from Google Calendars"
  task cleanup_tbd_calendar_events: :environment do
    puts "Running CleanupDuplicateTbdEventsJob for all users..."
    CleanupDuplicateTbdEventsJob.perform_now
    puts "Done. Check logs for details."
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
