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
end
