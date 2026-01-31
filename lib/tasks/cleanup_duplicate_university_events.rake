# frozen_string_literal: true

namespace :university_calendar do
  desc "Clean up duplicate university calendar events (including fuzzy matches)"
  task cleanup_duplicates: :environment do
    puts "=== Cleaning up duplicate university calendar events ==="
    puts "Using fuzzy matching (#{(UniversityCalendarEvent::SIMILARITY_THRESHOLD * 100).to_i}% similarity threshold)"
    puts "Organization priority: Registrar's Office > Academic Affairs > Student Affairs > Center for Wellness > Others"
    puts ""

    removed_count = 0
    kept_count = 0
    processed_ids = Set.new

    # Group events by date and category to reduce comparison scope
    grouped_by_day = UniversityCalendarEvent.all.group_by do |event|
      [event.start_time.to_date, event.end_time.to_date, event.category]
    end

    # Process each day/category group
    grouped_by_day.each do |key, events_in_group|
      date_start, date_end, category = key

      # Find duplicate clusters within this group using fuzzy matching
      events_to_process = events_in_group.reject { |e| processed_ids.include?(e.id) }

      events_to_process.each do |event|
        next if processed_ids.include?(event.id)

        # Find all fuzzy duplicates for this event
        duplicates = events_to_process.select do |other|
          next false if event.id == other.id
          next false if processed_ids.include?(other.id)

          event.fuzzy_duplicate_of?(other)
        end

        next if duplicates.empty?

        # Include the original event in the group
        duplicate_group = [event] + duplicates

        puts "\nFound #{duplicate_group.size} similar events:"
        puts "  Date: #{date_start}"
        puts "  Category: #{category}"

        # Use the preferred_event method to determine which to keep
        keeper = UniversityCalendarEvent.preferred_event(duplicate_group)
        to_remove = duplicate_group - [keeper]

        puts "  Keeping: '#{keeper.summary}' (#{keeper.organization || 'No org'}, #{keeper.ics_uid})"
        kept_count += 1
        processed_ids << keeper.id

        to_remove.each do |dup|
          similarity = UniversityCalendarEvent.similarity(keeper.summary, dup.summary)
          puts "  Removing: '#{dup.summary}' (#{dup.organization || 'No org'}, #{(similarity * 100).to_i}% similar, #{dup.ics_uid})"

          # Transfer GoogleCalendarEvent associations to the keeper
          # Handle unique constraint by deleting conflicts instead of transferring
          keeper_calendar_ids = keeper.google_calendar_events.pluck(:google_calendar_id)

          dup.google_calendar_events.find_each do |gcal_event|
            if keeper_calendar_ids.include?(gcal_event.google_calendar_id)
              # Keeper already has an event for this calendar, delete the duplicate's
              gcal_event.destroy
            else
              # No conflict, safe to transfer
              gcal_event.update_column(:university_calendar_event_id, keeper.id) # rubocop:disable Rails/SkipsModelValidations
            end
          end

          # Delete the duplicate
          dup.destroy
          removed_count += 1
          processed_ids << dup.id
        end
      end
    end

    puts "\n=== Cleanup Complete ==="
    puts "Events kept: #{kept_count}"
    puts "Duplicates removed: #{removed_count}"

    if removed_count > 0
      puts "\nTriggering calendar sync for all users to update Google Calendar..."
      User.joins(oauth_credentials: :google_calendar).distinct.find_each do |user|
        GoogleCalendarSyncJob.perform_later(user, force: true)
      end
      puts "Calendar sync jobs queued."
    end
  end

  desc "Check for duplicate university calendar events (dry run, including fuzzy matches)"
  task check_duplicates: :environment do
    puts "=== Checking for duplicate university calendar events ==="
    puts "Using fuzzy matching (#{(UniversityCalendarEvent::SIMILARITY_THRESHOLD * 100).to_i}% similarity threshold)"
    puts ""

    total_events = UniversityCalendarEvent.count
    duplicate_groups = 0
    duplicate_count = 0
    processed_ids = Set.new

    # Group events by date and category
    grouped_by_day = UniversityCalendarEvent.all.group_by do |event|
      [event.start_time.to_date, event.end_time.to_date, event.category]
    end

    # Find duplicate clusters
    grouped_by_day.each do |key, events_in_group|
      date_start, date_end, category = key
      events_to_process = events_in_group.reject { |e| processed_ids.include?(e.id) }

      events_to_process.each do |event|
        next if processed_ids.include?(event.id)

        # Find all fuzzy duplicates
        duplicates = events_to_process.select do |other|
          next false if event.id == other.id
          next false if processed_ids.include?(other.id)

          event.fuzzy_duplicate_of?(other)
        end

        next if duplicates.empty?

        duplicate_group = [event] + duplicates
        duplicate_groups += 1
        duplicate_count += (duplicate_group.size - 1)

        puts "\nDuplicate group (#{duplicate_group.size} events):"
        puts "  Date: #{date_start.strftime('%Y-%m-%d')}"
        puts "  Category: #{category}"
        puts "  Events:"

        keeper = UniversityCalendarEvent.preferred_event(duplicate_group)
        duplicate_group.each do |e|
          is_keeper = (e.id == keeper.id)
          similarity = if e.id == event.id
                         100
                       else
                         (UniversityCalendarEvent.similarity(event.summary, e.summary) * 100).to_i
                       end
          status = is_keeper ? "[KEEP]" : "[REMOVE]"
          puts "    #{status} '#{e.summary}' (#{e.organization || 'No org'}, #{similarity}% similar)"
        end

        duplicate_group.each { |e| processed_ids << e.id }
      end
    end

    puts "\n=== Summary ==="
    puts "Total events: #{total_events}"
    puts "Duplicate groups: #{duplicate_groups}"
    puts "Duplicate events to remove: #{duplicate_count}"

    if duplicate_count > 0
      puts "\nRun 'rails university_calendar:cleanup_duplicates' to remove duplicates."
    else
      puts "\nNo duplicates found!"
    end
  end

  desc "Check for orphaned GoogleCalendarEvent records (dry run)"
  task check_orphaned_gcal_events: :environment do
    puts "=== Checking for orphaned Google Calendar events ==="
    puts ""

    # Find GoogleCalendarEvent records pointing to non-existent UniversityCalendarEvents
    orphaned = GoogleCalendarEvent.left_joins(:university_calendar_event)
                                   .where(university_calendar_events: { id: nil })
                                   .where.not(university_calendar_event_id: nil)

    puts "Total GoogleCalendarEvent records: #{GoogleCalendarEvent.count}"
    puts "Orphaned records found: #{orphaned.count}"
    puts ""

    if orphaned.any?
      # Group by calendar for better output
      by_calendar = orphaned.group_by(&:google_calendar_id)

      by_calendar.each do |calendar_id, events|
        calendar = GoogleCalendar.find_by(id: calendar_id)
        user_email = calendar&.oauth_credential&.user&.email || "Unknown"

        puts "Calendar ID #{calendar_id} (User: #{user_email}):"
        puts "  #{events.count} orphaned events"

        # Show sample events
        events.first(5).each do |gce|
          puts "    - DB ID: #{gce.id}, GoogleEventID: #{gce.google_event_id}, Missing UniversityEvent: #{gce.university_calendar_event_id}"
        end

        puts "    ... and #{events.count - 5} more" if events.count > 5
        puts ""
      end

      puts "\nThese orphaned records are causing duplicate events in Google Calendar."
      puts "They reference UniversityCalendarEvent records that no longer exist."
      puts "\nRun 'rails university_calendar:cleanup_orphaned_gcal_events' to remove them."
    else
      puts "No orphaned records found!"
    end
  end

  desc "Clean up orphaned GoogleCalendarEvent records"
  task cleanup_orphaned_gcal_events: :environment do
    puts "=== Cleaning up orphaned Google Calendar events ==="
    puts ""

    # Find orphaned records
    orphaned = GoogleCalendarEvent.left_joins(:university_calendar_event)
                                   .where(university_calendar_events: { id: nil })
                                   .where.not(university_calendar_event_id: nil)

    total = orphaned.count
    puts "Found #{total} orphaned GoogleCalendarEvent records"

    if total.zero?
      puts "No orphaned events to clean up."
    else
      deleted_from_gcal = 0
      deleted_from_db = 0
      errors = 0

      orphaned.find_each do |gce|
        begin
          calendar = gce.google_calendar
          next unless calendar

          # Delete from Google Calendar
          service = GoogleCalendarService.new(calendar.oauth_credential)
          begin
            service.delete_event(calendar.calendar_id, gce.google_event_id)
            deleted_from_gcal += 1
            puts "Deleted from Google Calendar: #{gce.google_event_id} (Calendar: #{calendar.id})"
          rescue Google::Apis::ClientError => e
            if e.status_code == 404 || e.status_code == 410
              # Event already deleted from Google Calendar, just clean up DB
              puts "Event already gone from Google Calendar: #{gce.google_event_id}"
            else
              raise
            end
          end

          # Delete from database
          gce.destroy
          deleted_from_db += 1
        rescue => e
          errors += 1
          puts "Error processing GoogleCalendarEvent #{gce.id}: #{e.message}"
          Rails.logger.error("Failed to cleanup orphaned GoogleCalendarEvent #{gce.id}: #{e.message}")
        end
      end

      puts "\n=== Cleanup Complete ==="
      puts "Deleted from Google Calendar: #{deleted_from_gcal}"
      puts "Deleted from database: #{deleted_from_db}"
      puts "Errors: #{errors}"

      if deleted_from_db > 0
        puts "\nTriggering calendar sync for all users to ensure consistency..."
        User.joins(oauth_credentials: :google_calendar).distinct.find_each do |user|
          GoogleCalendarSyncJob.perform_later(user, force: true)
        end
        puts "Calendar sync jobs queued."
      end
    end
  end

  desc "Check for ghost events in Google Calendar (exist in GCal but not in our database)"
  task check_ghost_events: :environment do
    puts "=== Checking for ghost events in Google Calendar ==="
    puts "These are events that exist in Google Calendar but aren't tracked in our database"
    puts ""

    total_ghost_events = 0
    total_tracked_events = 0

    GoogleCalendar.find_each do |calendar|
      user_email = calendar.oauth_credential&.user&.email || "Unknown"
      puts "\nChecking calendar #{calendar.id} (User: #{user_email})..."

      begin
        service = GoogleCalendarService.new(calendar.oauth_credential)

        # Fetch all university calendar events from Google Calendar
        gcal_events = service.list_events(calendar.calendar_id)

        # Get all tracked event IDs for this calendar
        tracked_event_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set

        # Find events in GCal that aren't tracked in our DB
        ghost_events = gcal_events.reject { |e| tracked_event_ids.include?(e.id) }

        total_tracked_events += tracked_event_ids.size
        total_ghost_events += ghost_events.size

        if ghost_events.any?
          puts "  Found #{ghost_events.size} ghost events (out of #{gcal_events.size} total events)"

          # Show details of ghost events
          ghost_events.first(10).each do |event|
            puts "    - #{event.summary} (#{event.start&.date_time || event.start&.date}) [ID: #{event.id}]"
          end

          puts "    ... and #{ghost_events.size - 10} more" if ghost_events.size > 10
        else
          puts "  No ghost events found (#{gcal_events.size} events, all tracked)"
        end
      rescue => e
        puts "  Error checking calendar: #{e.message}"
        Rails.logger.error("Failed to check ghost events for calendar #{calendar.id}: #{e.message}")
      end
    end

    puts "\n=== Summary ==="
    puts "Total tracked events in database: #{total_tracked_events}"
    puts "Total ghost events in Google Calendar: #{total_ghost_events}"

    if total_ghost_events > 0
      puts "\nThese ghost events are likely causing duplicates."
      puts "Run 'rails university_calendar:cleanup_ghost_events' to remove them."
    else
      puts "\nNo ghost events found!"
    end
  end

  desc "Clean up ghost events in Google Calendar (exist in GCal but not in our database)"
  task cleanup_ghost_events: :environment do
    puts "=== Cleaning up ghost events in Google Calendar ==="
    puts ""

    total_deleted = 0
    total_errors = 0

    GoogleCalendar.find_each do |calendar|
      user_email = calendar.oauth_credential&.user&.email || "Unknown"
      puts "\nProcessing calendar #{calendar.id} (User: #{user_email})..."

      begin
        service = GoogleCalendarService.new(calendar.oauth_credential)

        # Fetch all university calendar events from Google Calendar
        gcal_events = service.list_events(calendar.calendar_id)

        # Get all tracked event IDs for this calendar
        tracked_event_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set

        # Find events in GCal that aren't tracked in our DB
        ghost_events = gcal_events.reject { |e| tracked_event_ids.include?(e.id) }

        if ghost_events.any?
          puts "  Deleting #{ghost_events.size} ghost events..."

          ghost_events.each do |event|
            begin
              service.delete_event(calendar.calendar_id, event.id)
              total_deleted += 1
              puts "    Deleted: #{event.summary} [ID: #{event.id}]"
            rescue => e
              total_errors += 1
              puts "    Error deleting #{event.id}: #{e.message}"
              Rails.logger.error("Failed to delete ghost event #{event.id}: #{e.message}")
            end
          end
        else
          puts "  No ghost events to delete"
        end
      rescue => e
        puts "  Error processing calendar: #{e.message}"
        Rails.logger.error("Failed to cleanup ghost events for calendar #{calendar.id}: #{e.message}")
      end
    end

    puts "\n=== Cleanup Complete ==="
    puts "Ghost events deleted: #{total_deleted}"
    puts "Errors: #{total_errors}"

    if total_deleted > 0
      puts "\nTriggering calendar sync for all users to ensure consistency..."
      User.joins(oauth_credentials: :google_calendar).distinct.find_each do |user|
        GoogleCalendarSyncJob.perform_later(user, force: true)
      end
      puts "Calendar sync jobs queued."
    end
  end
end
