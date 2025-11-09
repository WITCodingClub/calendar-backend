# frozen_string_literal: true

namespace :debug do
  desc "Debug reminder settings for a specific user's calendar events"
  task :reminders, [:user_email] => :environment do |_t, args|
    user_email = args[:user_email] || ENV["USER_EMAIL"]

    unless user_email
      puts "Usage: rails debug:reminders[user@example.com]"
      puts "   or: USER_EMAIL=user@example.com rails debug:reminders"
      exit 1
    end

    user = User.find_by_email(user_email)
    unless user
      puts "User not found: #{user_email}"
      exit 1
    end

    puts "=" * 80
    puts "Debugging Reminder Settings for: #{user.email}"
    puts "=" * 80

    # Check calendar preferences
    puts "\n--- Calendar Preferences ---"
    user.calendar_preferences.each do |pref|
      puts "Scope: #{pref.scope} (#{pref.event_type || 'global'})"
      puts "  Reminder Settings: #{pref.reminder_settings.inspect}"
    end

    if user.calendar_preferences.empty?
      puts "No calendar preferences found - using system defaults"
      puts "System default: #{PreferenceResolver::SYSTEM_DEFAULTS[:reminder_settings].inspect}"
    end

    # Check a sample event
    google_calendar = user.google_credential&.google_calendar
    unless google_calendar
      puts "\nNo Google Calendar found for this user"
      exit 0
    end

    sample_event = google_calendar.google_calendar_events.first
    unless sample_event
      puts "\nNo calendar events found"
      exit 0
    end

    puts "\n--- Sample Event Analysis ---"
    puts "Event ID: #{sample_event.google_event_id}"
    puts "Summary: #{sample_event.summary}"
    puts "Meeting Time ID: #{sample_event.meeting_time_id}"

    if sample_event.meeting_time
      puts "\n--- Preference Resolution for Sample Event ---"
      resolver = PreferenceResolver.new(user)
      prefs = resolver.resolve_for(sample_event.meeting_time)
      puts "Resolved reminder_settings: #{prefs[:reminder_settings].inspect}"

      puts "\n--- Preference Source ---"
      result = resolver.resolve_with_sources(sample_event.meeting_time)
      puts "Source: #{result[:sources][:reminder_settings]}"
    end

    puts "\n--- Fetching Event from Google Calendar API ---"
    begin
      service = GoogleCalendarService.new(user)
      # Use private method via send
      gcal_service = service.send(:service_account_calendar_service)
      gcal_event = gcal_service.get_event(google_calendar.google_calendar_id, sample_event.google_event_id)

      puts "Event Summary: #{gcal_event.summary}"
      if gcal_event.reminders
        puts "Reminders Use Default: #{gcal_event.reminders.use_default}"
        if gcal_event.reminders.overrides
          puts "Reminders Overrides:"
          gcal_event.reminders.overrides.each do |reminder|
            puts "  - #{reminder.reminder_method}: #{reminder.minutes} minutes"
          end
        else
          puts "No reminder overrides"
        end
      else
        puts "⚠️  NO REMINDERS SET ON THIS EVENT!"
      end
    rescue Google::Apis::Error => e
      puts "Error fetching event from Google Calendar: #{e.message}"
    end

    puts "\n" + "=" * 80
  end

  desc "Force re-sync all events for a user (applies current preferences including reminders)"
  task :force_sync_reminders, [:user_email] => :environment do |_t, args|
    user_email = args[:user_email] || ENV["USER_EMAIL"]

    unless user_email
      puts "Usage: rails debug:force_sync_reminders[user@example.com]"
      puts "   or: USER_EMAIL=user@example.com rails debug:force_sync_reminders"
      exit 1
    end

    user = User.find_by_email(user_email)
    unless user
      puts "User not found: #{user_email}"
      exit 1
    end

    puts "Force syncing all events for: #{user.email}"
    puts "This will apply current preferences (including reminders) to all events"
    print "Continue? (y/N): "
    response = $stdin.gets.chomp.downcase
    exit 0 unless response == "y"

    # Trigger a full sync with force=true
    GoogleCalendarSyncJob.perform_now(user, force: true)
    puts "✓ Sync complete!"
  end
end
