# frozen_string_literal: true

namespace :university_calendar do
  desc "Sync university calendar events from ICS feed"
  task sync: :environment do
    puts "Syncing university calendar..."
    result = UniversityCalendarIcsService.call
    puts "Results: Created: #{result[:created]}, Updated: #{result[:updated]}, Unchanged: #{result[:unchanged]}"
    puts "Errors: #{result[:errors].join(', ')}" if result[:errors].any?
  end

  desc "Extract term dates from university calendar events"
  task extract_term_dates: :environment do
    puts "Extracting term dates from university events..."

    Term.find_each do |term|
      dates = UniversityCalendarEvent.detect_term_dates(term.year, term.season)

      updates = {}
      updates[:start_date] = dates[:start_date] if dates[:start_date]
      updates[:end_date] = dates[:end_date] if dates[:end_date]

      if updates.any?
        term.update!(updates)
        puts "  #{term.name}: #{updates}"
      else
        puts "  #{term.name}: No dates found"
      end
    rescue => e
      puts "  #{term.name}: Error - #{e.message}"
    end
  end

  desc "Show upcoming holidays"
  task holidays: :environment do
    puts "Upcoming holidays:"
    UniversityCalendarEvent.holidays.upcoming.order(:start_time).limit(20).each do |event|
      puts "  #{event.start_time.strftime('%Y-%m-%d')}: #{event.summary}"
    end
  end

  desc "Show upcoming university events"
  task events: :environment do
    puts "Upcoming university events:"
    UniversityCalendarEvent.upcoming.order(:start_time).limit(30).each do |event|
      date = event.all_day ? event.start_time.strftime("%Y-%m-%d") : event.start_time.strftime("%Y-%m-%d %H:%M")
      puts "  [#{event.category}] #{date}: #{event.summary}"
    end
  end

  desc "Trigger calendar sync for all users with university events enabled"
  task sync_user_calendars: :environment do
    puts "Triggering calendar sync for users with university events enabled..."
    count = 0

    User.joins(:user_extension_config)
        .where(user_extension_configs: { sync_university_events: true })
        .joins(oauth_credentials: :google_calendar)
        .distinct
        .find_each do |user|
          GoogleCalendarSyncJob.perform_later(user, force: true)
          count += 1
    end

    puts "Queued sync for #{count} users"
  end

  desc "Show category distribution"
  task stats: :environment do
    puts "University Calendar Event Statistics:"
    puts "  Total events: #{UniversityCalendarEvent.count}"
    puts "  Upcoming events: #{UniversityCalendarEvent.upcoming.count}"
    puts "  Past events: #{UniversityCalendarEvent.past.count}"
    puts ""
    puts "  By category:"
    UniversityCalendarEvent.group(:category).count.each do |category, count|
      puts "    #{category || 'nil'}: #{count}"
    end
    puts ""
    puts "  Last fetched: #{UniversityCalendarEvent.maximum(:last_fetched_at)}"
  end

  desc "Retroactively restore past university calendar events (holidays, etc.) that were incorrectly deleted from user GCals"
  task restore_past_events: :environment do
    puts "Restoring past university calendar events deleted due to bug #360..."
    puts ""

    # Collect all past holidays - these should be in every user's calendar
    past_holidays = UniversityCalendarEvent.holidays.past.order(:start_time).to_a
    puts "Found #{past_holidays.size} past holidays to check"

    users_processed = 0
    events_restored = 0
    errors = []

    User.joins(oauth_credentials: :google_calendar).distinct.find_each do |user|
      google_calendar = GoogleCalendar.for_user(user).first
      next unless google_calendar

      begin
        # Find which past holiday IDs already have a GCal event record for this user
        existing_uni_event_ids = google_calendar.google_calendar_events
                                                .where.not(university_calendar_event_id: nil)
                                                .pluck(:university_calendar_event_id)

        # Find past holidays missing from this user's calendar
        missing_holidays = past_holidays.reject { |e| existing_uni_event_ids.include?(e.id) }

        # Also check opted-in non-holiday categories
        user_config = user.user_extension_config
        if user_config&.sync_university_events
          opted_categories = (user_config.university_event_categories || []) - ["holiday"]
          unless opted_categories.empty?
            past_opted_events = UniversityCalendarEvent.past
                                                       .by_categories(opted_categories)
                                                       .order(:start_time)
                                                       .to_a
            missing_opted = past_opted_events.reject { |e| existing_uni_event_ids.include?(e.id) }
            missing_holidays += missing_opted
          end
        end

        if missing_holidays.empty?
          puts "  User #{user.id} (#{user.email}): nothing to restore"
          users_processed += 1
          next
        end

        puts "  User #{user.id} (#{user.email}): restoring #{missing_holidays.size} events"

        events_to_add = missing_holidays.map do |event|
          {
            summary: event.category == "holiday" ? event.formatted_holiday_summary : event.summary,
            description: event.description,
            location: event.location,
            start_time: event.start_time,
            end_time: event.end_time,
            university_calendar_event_id: event.id,
            all_day: event.all_day || true,
            recurrence: nil
          }
        end

        service = GoogleCalendarService.new(user)
        result = service.update_specific_events(events_to_add, force: false)

        restored = result[:created] + result[:updated]
        events_restored += restored
        puts "    ✓ Restored #{restored} events (#{result[:created]} created, #{result[:updated]} updated, #{result[:skipped]} skipped)"
        users_processed += 1
      rescue => e
        errors << "User #{user.id}: #{e.message}"
        puts "    ✗ Error: #{e.message}"
      end
    end

    puts ""
    puts "=" * 60
    puts "Summary:"
    puts "  Users processed: #{users_processed}"
    puts "  Events restored: #{events_restored}"
    puts "  Errors: #{errors.size}"
    errors.each { |err| puts "    - #{err}" } if errors.any?
    puts ""
    puts "✓ Done! Past university calendar events have been restored."
  end

  desc "Fix term associations for term_dates events using date-based inference"
  task fix_term_associations: :environment do
    puts "Fixing term associations for term_dates events..."
    puts "This will correct events where the ICS academic_term field doesn't match the event date."
    puts ""

    fixed_count = 0
    checked_count = 0
    errors = []

    # Only process term_dates events (Classes Begin/End)
    UniversityCalendarEvent.term_dates.find_each do |event|
      checked_count += 1

      # Infer the correct term from the event date
      inferred_season = case event.start_time.month
                        when 1..5 then :spring
                        when 6..7 then :summer
                        when 8..12 then :fall
                        end

      year = event.start_time.year
      correct_term = Term.find_by(year: year, season: inferred_season)

      # Check if current term assignment is wrong
      if event.term_id != correct_term&.id
        old_term_name = event.term&.name || "nil"
        new_term_name = correct_term&.name || "nil"

        puts "  Fixing: '#{event.summary}' (#{event.start_time.to_date})"
        puts "    Academic Term field: #{event.academic_term}"
        puts "    Current term: #{old_term_name}"
        puts "    Correct term: #{new_term_name}"
        puts ""

        event.update_column(:term_id, correct_term&.id) # rubocop:disable Rails/SkipsModelValidations
        fixed_count += 1
      end
    rescue => e
      errors << "Error processing event #{event.id}: #{e.message}"
      puts "  Error: #{e.message}"
    end

    puts ""
    puts "=" * 60
    puts "Summary:"
    puts "  Events checked: #{checked_count}"
    puts "  Events fixed: #{fixed_count}"
    puts "  Errors: #{errors.count}"
    puts ""

    if errors.any?
      puts "Errors encountered:"
      errors.each { |err| puts "  - #{err}" }
      puts ""
    end

    if fixed_count > 0
      puts "✓ Term associations have been corrected!"
      puts ""
      puts "Next steps:"
      puts "  1. Run 'rake university_calendar:sync_user_calendars' to trigger calendar sync for all users"
      puts "  2. This will update Google Calendar events with the correct term information"
    else
      puts "✓ No corrections needed - all term associations are correct!"
    end
  end
end
