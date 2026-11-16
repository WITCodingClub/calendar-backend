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

  desc "Infer the category of every stored event again and print the changes. " \
       "ENV: DRY_RUN=0 saves them and queues the calendar syncs; without it the task only prints."
  task recategorize: :environment do
    # Only DRY_RUN=0 or false saves. Unset prints the changes only.
    apply = ENV["DRY_RUN"].present? && !ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    changes = UniversityCalendar::Recategorize.call(apply:)

    changes.each { |change| puts "  ##{change.event_id} #{change.summary.inspect}: #{change.from || 'none'} -> #{change.to}" }
    if changes.empty?
      puts "Every event already has the inferred category."
    elsif apply
      puts "Changed #{changes.size} events and queued the calendar syncs."
    else
      puts "Would change #{changes.size} events. Run again with DRY_RUN=0 to save them."
    end
  end
end
