# frozen_string_literal: true

namespace :university_calendar do
  desc "Clean up duplicate university calendar events (same content, different UIDs)"
  task cleanup_duplicates: :environment do
    puts "=== Cleaning up duplicate university calendar events ==="

    removed_count = 0
    kept_count = 0

    # Group events by content signature (summary + start_time + end_time + category)
    grouped_events = UniversityCalendarEvent.all.group_by do |event|
      [
        event.summary&.downcase&.strip,
        event.start_time,
        event.end_time,
        event.category
      ]
    end

    # Process each group
    grouped_events.each do |signature, events|
      next if events.size == 1  # No duplicates in this group

      puts "\nFound #{events.size} events with signature:"
      puts "  Summary: #{events.first.summary}"
      puts "  Start: #{events.first.start_time}"
      puts "  End: #{events.first.end_time}"
      puts "  Category: #{events.first.category}"

      # Sort by various criteria to determine which one to keep
      # Prefer: most recently fetched, then oldest created_at
      events_sorted = events.sort_by do |e|
        [
          e.last_fetched_at || Time.at(0),  # Most recently fetched (descending)
          -(e.created_at.to_i)               # Oldest created (ascending)
        ]
      end.reverse

      keeper = events_sorted.first
      duplicates = events_sorted[1..]

      puts "  Keeping: #{keeper.ics_uid} (created #{keeper.created_at})"
      kept_count += 1

      duplicates.each do |dup|
        puts "  Removing: #{dup.ics_uid} (created #{dup.created_at})"

        # Transfer any GoogleCalendarEvent associations to the keeper
        dup.google_calendar_events.update_all(university_calendar_event_id: keeper.id)

        # Delete the duplicate
        dup.destroy
        removed_count += 1
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

  desc "Check for duplicate university calendar events (dry run)"
  task check_duplicates: :environment do
    puts "=== Checking for duplicate university calendar events ==="

    total_events = UniversityCalendarEvent.count
    duplicate_groups = 0
    duplicate_count = 0

    # Group events by content signature
    grouped_events = UniversityCalendarEvent.all.group_by do |event|
      [
        event.summary&.downcase&.strip,
        event.start_time,
        event.end_time,
        event.category
      ]
    end

    # Find groups with duplicates
    grouped_events.each do |signature, events|
      next if events.size == 1

      duplicate_groups += 1
      duplicate_count += (events.size - 1)  # Count extras beyond the first

      puts "\nDuplicate group (#{events.size} events):"
      puts "  Summary: #{events.first.summary}"
      puts "  Start: #{events.first.start_time.strftime('%Y-%m-%d %H:%M')}"
      puts "  End: #{events.first.end_time.strftime('%Y-%m-%d %H:%M')}"
      puts "  Category: #{events.first.category}"
      puts "  UIDs:"
      events.each do |e|
        puts "    - #{e.ics_uid} (created #{e.created_at.strftime('%Y-%m-%d')})"
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
