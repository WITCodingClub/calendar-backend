# frozen_string_literal: true

namespace :university_calendar do
  desc "Import university calendar events from the 25Live ICS feed only: no user calendar syncs and no term dates " \
       "(UniversityCalendar::SyncJob does those)"
  task sync: :environment do
    result = UniversityCalendar::IcsImport.call
    puts "Sync complete: #{result}"
  end

  desc "Backfill historical university calendar events for a date range (e.g. rake university_calendar:backfill[2024-01-01,2024-12-31])"
  task :backfill, %i[start_date end_date] => :environment do |_t, args|
    start_date = Date.parse(args[:start_date])
    end_date   = Date.parse(args[:end_date])

    puts "Backfilling university calendar events from #{start_date} to #{end_date}..."
    result = UniversityCalendar::BackfillJob.perform_now(start_date, end_date)
    puts "Backfill complete: #{result}"
  end
end
