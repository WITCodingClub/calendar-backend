# frozen_string_literal: true

# One-time cleanup task to fix location display issues caused by empty building records.
# This task should be run after deploying the tbd_building? fix to clean up existing data.
#
# The bug: LeopardWeb sends null/empty building data for unassigned locations, but our
# tbd_building? check only looked for "tbd" or "to be determined" strings, not empty values.
# This caused empty-building MeetingTimes to be treated as valid locations instead of TBD.

namespace :cleanup do
  desc "Diagnose empty building issues - show what would be cleaned up (dry run)"
  task diagnose_empty_buildings: :environment do
    puts "Diagnosing empty building issues..."
    puts "=" * 60

    # Find buildings with empty name or abbreviation
    empty_buildings = Building.where("name = '' OR abbreviation = '' OR name IS NULL OR abbreviation IS NULL")
    puts "\nEmpty/null buildings found: #{empty_buildings.count}"
    empty_buildings.each do |b|
      meeting_time_count = MeetingTime.joins(:room).where(rooms: { building_id: b.id }).count
      puts "  Building ID #{b.id}: name='#{b.name}' abbr='#{b.abbreviation}' - #{meeting_time_count} meeting times"
    end

    # Find courses that have both empty-building and valid-building meeting times
    puts "\nCourses with both empty and valid locations (potential duplicates):"

    duplicates_found = 0
    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }

      grouped.each do |(day, begin_t, end_t), mts|
        next if mts.size <= 1

        empty_building_mts = mts.select { |mt| mt.building&.name.blank? || mt.building&.abbreviation.blank? }
        valid_building_mts = mts.reject { |mt| mt.building&.name.blank? || mt.building&.abbreviation.blank? }

        if empty_building_mts.any? && valid_building_mts.any?
          duplicates_found += 1
          puts "  Course: #{course.crn} - #{course.title}"
          puts "    Day: #{day}, Time: #{begin_t}-#{end_t}"
          puts "    Empty building MeetingTimes: #{empty_building_mts.map(&:id).join(', ')}"
          puts "    Valid building MeetingTimes: #{valid_building_mts.map(&:id).join(', ')}"
          valid_building_mts.each do |mt|
            puts "      -> #{mt.building.abbreviation} #{mt.room.number}"
          end
        end
      end
    end

    puts "\nTotal duplicate groups found: #{duplicates_found}"

    # Show users who might have duplicate calendar events
    puts "\nUsers with Google Calendar events pointing to empty-building meeting times:"
    affected_users = User.joins(google_calendars: { google_calendar_events: { meeting_time: { room: :building } } })
                         .where("buildings.name = '' OR buildings.abbreviation = '' OR buildings.name IS NULL OR buildings.abbreviation IS NULL")
                         .distinct
    puts "  #{affected_users.count} users affected"
    affected_users.limit(10).each do |user|
      event_count = GoogleCalendarEvent.joins(meeting_time: { room: :building })
                                        .joins(:google_calendar)
                                        .where(google_calendars: { oauth_credential_id: user.oauth_credentials.pluck(:id) })
                                        .where("buildings.name = '' OR buildings.abbreviation = ''")
                                        .count
      puts "    User #{user.id} (#{user.email}): #{event_count} events with empty buildings"
    end

    puts "\n" + "=" * 60
    puts "Run 'rails cleanup:fix_empty_building_duplicates' to remove duplicate MeetingTimes"
    puts "Then run 'rails cleanup:sync_affected_users' to update their calendars"
  end

  desc "Remove duplicate MeetingTimes where valid location exists alongside empty-building version"
  task fix_empty_building_duplicates: :environment do
    puts "Fixing empty building duplicates..."

    deleted_count = 0
    events_deleted = 0

    Course.includes(meeting_times: { room: :building }).find_each do |course|
      grouped = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }

      grouped.each do |(day, begin_t, end_t), mts|
        next if mts.size <= 1

        empty_building_mts = mts.select { |mt| mt.building&.name.blank? || mt.building&.abbreviation.blank? }
        valid_building_mts = mts.reject { |mt| mt.building&.name.blank? || mt.building&.abbreviation.blank? }

        # Only delete empty-building MTs if we have a valid one to keep
        if empty_building_mts.any? && valid_building_mts.any?
          empty_building_mts.each do |mt|
            # Count associated calendar events that will be deleted
            events_deleted += mt.google_calendar_events.count

            puts "  Deleting MeetingTime #{mt.id} for course #{course.crn} (empty building, valid location exists)"
            mt.destroy!
            deleted_count += 1
          end
        end
      end
    end

    puts "\nDeleted #{deleted_count} duplicate MeetingTimes with empty buildings"
    puts "Deleted #{events_deleted} associated GoogleCalendarEvents (they'll be recreated on next sync)"
    puts "\nRun 'rails cleanup:sync_affected_users' to update affected user calendars"
  end

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
