# frozen_string_literal: true

namespace :university_calendar do
  desc "Sync university calendar events from the 25Live ICS feed"
  task sync: :environment do
    result = UniversityCalendarIcsService.call
    puts "Sync complete: #{result}"
  end

  desc "Backfill historical university calendar events for a date range (e.g. rake university_calendar:backfill[2024-01-01,2024-12-31])"
  task :backfill, %i[start_date end_date] => :environment do |_t, args|
    start_date = Date.parse(args[:start_date])
    end_date   = Date.parse(args[:end_date])

    puts "Backfilling university calendar events from #{start_date} to #{end_date}..."

    url    = UniversityCalendarIcsService.backfill_url(start_date, end_date)
    result = UniversityCalendarIcsService.call(ics_url: url)

    puts "Backfill complete: #{result}"
  end
end
