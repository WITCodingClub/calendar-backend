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

  desc "Sync finals for a specific term to all users' calendars (retroactive)"
  task :sync_finals_for_term, [:year, :season] => :environment do |_t, args|
    unless args[:year] && args[:season]
      puts "Usage: rails calendar:sync_finals_for_term[2025,fall]"
      puts "Seasons: spring, summer, fall"
      exit 1
    end

    year = args[:year].to_i
    season = args[:season].to_sym

    term = Term.find_by(year: year, season: season)
    unless term
      puts "Term not found: #{season.to_s.capitalize} #{year}"
      exit 1
    end

    puts "Syncing finals for #{term.name}..."
    puts ""

    users_with_calendars = User.joins(oauth_credentials: :google_calendar)
                               .where(oauth_credentials: { provider: "google" })
                               .distinct

    puts "Found #{users_with_calendars.count} users with calendars"
    puts ""

    synced_count = 0
    skipped_count = 0
    error_count = 0

    users_with_calendars.find_each do |user|
      # Build finals for this specific term
      enrolled_course_ids = user.enrollments.joins(:course)
                                .where(courses: { term_id: term.id })
                                .pluck(:course_id)

      if enrolled_course_ids.empty?
        skipped_count += 1
        next
      end

      finals_events = FinalExam.where(course_id: enrolled_course_ids)
                               .includes(course: :faculties)
                               .filter_map do |final_exam|
        next unless final_exam.start_datetime && final_exam.end_datetime
        {
          summary: "Final Exam: #{final_exam.course_title}",
          description: final_exam.course_code,
          location: final_exam.location,
          start_time: final_exam.start_datetime,
          end_time: final_exam.end_datetime,
          course_code: final_exam.course_code,
          final_exam_id: final_exam.id,
          recurrence: nil
        }
      end

      if finals_events.empty?
        skipped_count += 1
        next
      end

      begin
        GoogleCalendarService.new(user).update_specific_events(finals_events, force: true)
        puts "✓ User #{user.id} (#{user.email}): Synced #{finals_events.count} finals"
        synced_count += 1
      rescue Signet::AuthorizationError => e
        puts "⚠ User #{user.id} (#{user.email}): OAuth expired - user needs to re-authenticate"
        error_count += 1
      rescue Google::Apis::ClientError => e
        puts "⚠ User #{user.id} (#{user.email}): Google API error - #{e.message}"
        error_count += 1
      rescue NoMethodError => e
        puts "✗ User #{user.id} (#{user.email}): NoMethodError - #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(5).join("\n            ")}"
        error_count += 1
      rescue => e
        puts "✗ User #{user.id} (#{user.email}): #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(5).join("\n            ")}"
        error_count += 1
      end
    end

    puts ""
    puts "Sync complete!"
    puts "  Synced: #{synced_count} users"
    puts "  Skipped: #{skipped_count} users (no enrollments or finals)"
    puts "  Errors: #{error_count} users"
  end

  desc "Force sync all calendars for all users"
  task force_sync_all: :environment do
    puts "Force syncing all user calendars..."
    puts ""

    users_with_calendars = User.joins(oauth_credentials: :google_calendar)
                               .where(oauth_credentials: { provider: "google" })
                               .distinct

    puts "Found #{users_with_calendars.count} users with calendars"
    puts ""

    synced_count = 0
    error_count = 0

    users_with_calendars.find_each do |user|
      begin
        user.sync_course_schedule(force: true)
        puts "✓ User #{user.id} (#{user.email}): Synced"
        synced_count += 1
      rescue => e
        puts "✗ User #{user.id} (#{user.email}): #{e.message}"
        error_count += 1
      end
    end

    puts ""
    puts "Sync complete!"
    puts "  Synced: #{synced_count} users"
    puts "  Errors: #{error_count} users"
  end
end
