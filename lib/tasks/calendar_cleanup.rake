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
        puts "  Processing #{finals_events.count} finals for User #{user.id}..."

        # Debug: Check calendar state
        google_cal = user.google_credential&.google_calendar
        puts "    Calendar ID: #{google_cal&.google_calendar_id}"
        puts "    Existing events in DB: #{google_cal&.google_calendar_events&.count || 0}"

        service = GoogleCalendarService.new(user)

        # Try to verify calendar exists on Google
        begin
          cal_service = Google::Apis::CalendarV3::CalendarService.new
          cal_service.authorization = service.send(:service_account_credentials)
          cal_info = cal_service.get_calendar(google_cal.google_calendar_id)
          puts "    Calendar verified on Google: #{cal_info.summary}"
        rescue Google::Apis::ClientError => e
          puts "    WARNING: Calendar verification failed: #{e.message}"
        end
        user_synced = 0
        user_errors = 0

        # Test 1: Service account credentials (minimal event)
        begin
          test_service = Google::Apis::CalendarV3::CalendarService.new
          test_service.authorization = service.send(:service_account_credentials)
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: "Test Event (Service Account)",
            start: { date_time: Time.current.iso8601, time_zone: "America/New_York" },
            end: { date_time: (Time.current + 1.hour).iso8601, time_zone: "America/New_York" }
          )
          result = test_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [SA] Test event created: #{result.id}"
          test_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [SA] Test event deleted"
        rescue => e
          puts "    [SA] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        # Test 2: User OAuth credentials (minimal event)
        begin
          user_service = service.send(:user_calendar_service)
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: "Test Event (User OAuth)",
            start: { date_time: Time.current.iso8601, time_zone: "America/New_York" },
            end: { date_time: (Time.current + 1.hour).iso8601, time_zone: "America/New_York" }
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [User] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [User] Test event deleted"
        rescue => e
          puts "    [User] TEST FAILED: #{e.class.name} - #{e.message}"
          puts "    Backtrace: #{e.backtrace.first(3).join("\n              ")}"
        end

        # Test 3: Event with reminders (like finals have)
        begin
          user_service = service.send(:user_calendar_service)
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: "Test With Reminders",
            start: { date_time: Time.current.iso8601, time_zone: "America/New_York" },
            end: { date_time: (Time.current + 1.hour).iso8601, time_zone: "America/New_York" }
          )
          test_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
            use_default: false,
            overrides: [
              Google::Apis::CalendarV3::EventReminder.new(reminder_method: "popup", minutes: 15)
            ]
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [Reminders] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [Reminders] Test event deleted"
        rescue => e
          puts "    [Reminders] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        # Test 4: Event with color
        begin
          user_service = service.send(:user_calendar_service)
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: "Test With Color",
            start: { date_time: Time.current.iso8601, time_zone: "America/New_York" },
            end: { date_time: (Time.current + 1.hour).iso8601, time_zone: "America/New_York" },
            color_id: "11"
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [Color] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [Color] Test event deleted"
        rescue => e
          puts "    [Color] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        # Test 5: Full finals-like event (but direct, not through update_specific_events)
        begin
          user_service = service.send(:user_calendar_service)
          final = finals_events.first
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: final[:summary],
            description: final[:description],
            location: final[:location],
            start: { date_time: final[:start_time].iso8601, time_zone: "America/New_York" },
            end: { date_time: final[:end_time].iso8601, time_zone: "America/New_York" },
            color_id: "11"
          )
          test_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
            use_default: false,
            overrides: [
              Google::Apis::CalendarV3::EventReminder.new(reminder_method: "popup", minutes: 15)
            ]
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [Full Direct] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [Full Direct] Test event deleted"
        rescue => e
          puts "    [Full Direct] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        # Test 6: Event with recurrence: nil (like create_event_in_calendar does for finals)
        begin
          user_service = service.send(:user_calendar_service)
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: "Test With recurrence: nil",
            start: { date_time: Time.current.iso8601, time_zone: "America/New_York" },
            end: { date_time: (Time.current + 1.hour).iso8601, time_zone: "America/New_York" },
            recurrence: nil  # Explicitly nil like finals
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [recurrence:nil] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [recurrence:nil] Test event deleted"
        rescue => e
          puts "    [recurrence:nil] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        # Test 7: Full event exactly like create_event_in_calendar builds it
        begin
          user_service = service.send(:user_calendar_service)
          final = finals_events.first
          # Mimic exactly what create_event_in_calendar does
          test_event = Google::Apis::CalendarV3::Event.new(
            summary: final[:summary],
            description: final[:description],
            location: final[:location],
            start: { date_time: final[:start_time].in_time_zone("America/New_York").iso8601, time_zone: "America/New_York" },
            end: { date_time: final[:end_time].in_time_zone("America/New_York").iso8601, time_zone: "America/New_York" },
            color_id: "11",
            recurrence: nil  # Finals have nil recurrence
          )
          # Apply finals default reminders (3 reminders)
          test_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
            use_default: false,
            overrides: [
              Google::Apis::CalendarV3::EventReminder.new(reminder_method: "popup", minutes: 1440), # 1 day
              Google::Apis::CalendarV3::EventReminder.new(reminder_method: "popup", minutes: 60),   # 1 hour
              Google::Apis::CalendarV3::EventReminder.new(reminder_method: "popup", minutes: 15)    # 15 min
            ]
          )
          result = user_service.insert_event(google_cal.google_calendar_id, test_event)
          puts "    [Exact Copy] Test event created: #{result.id}"
          user_service.delete_event(google_cal.google_calendar_id, result.id)
          puts "    [Exact Copy] Test event deleted"
        rescue => e
          puts "    [Exact Copy] TEST FAILED: #{e.class.name} - #{e.message}"
        end

        finals_events.each_with_index do |event, idx|
          begin
            puts "    Final #{idx + 1}: #{event[:summary]} at #{event[:start_time]}"
            service.update_specific_events([event], force: true)
            user_synced += 1
          rescue => e
            puts "      ERROR: #{e.class.name} - #{e.message}"
            user_errors += 1
          end
        end

        if user_errors == 0
          puts "✓ User #{user.id} (#{user.email}): Synced #{user_synced} finals"
          synced_count += 1
        else
          puts "⚠ User #{user.id} (#{user.email}): Synced #{user_synced}, failed #{user_errors}"
          error_count += 1
        end
      rescue Signet::AuthorizationError => e
        puts "⚠ User #{user.id} (#{user.email}): OAuth expired - user needs to re-authenticate"
        error_count += 1
      rescue => e
        puts "✗ User #{user.id} (#{user.email}): #{e.class.name} - #{e.message}"
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
