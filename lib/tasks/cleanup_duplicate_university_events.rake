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

          # Transfer any GoogleCalendarEvent associations to the keeper
          dup.google_calendar_events.update_all(university_calendar_event_id: keeper.id)

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
end
