# frozen_string_literal: true

namespace :calendar do
  desc "Delete all old calendars from Google using PaperTrail history"
  task cleanup_deleted_calendars: :environment do
    puts "Finding deleted calendars from PaperTrail..."

    deleted_versions = PaperTrail::Version.where(
      item_type: "GoogleCalendar",
      event: "destroy"
    )

    puts "Found #{deleted_versions.count} deleted calendars"

    deleted_versions.each do |version|
      begin
        # Parse the deleted calendar data
        calendar_data = YAML.unsafe_load(version.object)
        calendar_id = calendar_data["google_calendar_id"]

        puts "\nProcessing calendar: #{calendar_id}"

        # Try to delete from Google
        service = GoogleCalendarService.new
        service.delete_calendar(calendar_id)

        puts "  ✓ Successfully deleted from Google"
      rescue Google::Apis::ClientError => e
        if e.status_code == 404
          puts "  ⓘ Calendar not found in Google (already deleted)"
        else
          puts "  ✗ Failed to delete: #{e.message}"
        end
      rescue => e
        puts "  ✗ Error: #{e.message}"
      end
    end

    puts "\n✓ Cleanup complete!"
  end

  desc "List all deleted calendars from PaperTrail"
  task list_deleted_calendars: :environment do
    puts "Deleted calendars in PaperTrail:\n\n"

    PaperTrail::Version.where(
      item_type: "GoogleCalendar",
      event: "destroy"
    ).each do |version|
      calendar_data = YAML.unsafe_load(version.object)
      puts "  ID: #{calendar_data['google_calendar_id']}"
      puts "  Summary: #{calendar_data['summary']}"
      puts "  Deleted at: #{version.created_at}"
      puts "  ---"
    end
  end

  desc "List all orphaned calendars (exist in Google but not in database)"
  task list_orphaned_calendars: :environment do
    puts "Finding orphaned calendars...\n"

    service = GoogleCalendarService.new
    google_calendars = service.list_calendars

    # Get all calendar IDs from database
    db_calendar_ids = GoogleCalendar.pluck(:google_calendar_id)

    puts "Calendars in Google: #{google_calendars.items.count}"
    puts "Calendars in database: #{db_calendar_ids.count}\n\n"

    orphaned = []
    google_calendars.items.each do |cal|
      unless db_calendar_ids.include?(cal.id)
        orphaned << cal
        puts "  📅 #{cal.summary}"
        puts "     ID: #{cal.id}"
        puts "     ---"
      end
    end

    puts "\n#{orphaned.count} orphaned calendar(s) found"
  end

  desc "Delete all orphaned calendars from Google"
  task cleanup_orphaned_calendars: :environment do
    puts "Finding orphaned calendars...\n"

    service = GoogleCalendarService.new
    google_calendars = service.list_calendars

    # Get all calendar IDs from database
    db_calendar_ids = GoogleCalendar.pluck(:google_calendar_id)

    orphaned = []
    google_calendars.items.each do |cal|
      orphaned << cal unless db_calendar_ids.include?(cal.id)
    end

    puts "Found #{orphaned.count} orphaned calendar(s)\n\n"

    orphaned.each do |cal|
      puts "Deleting: #{cal.summary}"
      puts "  ID: #{cal.id}"

      begin
        service.delete_calendar(cal.id)
        puts "  ✓ Successfully deleted"
      rescue Google::Apis::ClientError => e
        puts "  ✗ Failed to delete: #{e.message}"
      rescue => e
        puts "  ✗ Error: #{e.message}"
      end
      puts ""
    end

    puts "✓ Cleanup complete!"
  end
end
