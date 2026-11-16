# frozen_string_literal: true

namespace :catalog do
  desc "Queue a calendar sync for every user with a course calendar and a course in a term"
  task :sync_calendars, [ :term_uid ] => :environment do |_, args|
    term_uid = args[:term_uid]
    raise "Usage: rake catalog:sync_calendars[term_uid]" unless term_uid

    term  = Term.find_by_uid!(term_uid)
    users = CourseCalendars::ResyncAudience.enrolled_in(term.id)

    puts "Queueing calendar syncs for #{users.count} users in term #{term.name}..."
    batch = CourseCalendars::SyncJob.perform_bulk_in_batch(users, reason: "manual")
    puts "Queued as batch #{batch.id}"
  end
end
