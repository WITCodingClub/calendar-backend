# frozen_string_literal: true

namespace :catalog do
  desc "Trigger immediate calendar syncs for all users enrolled in a term"
  task :sync_calendars, [ :term_uid ] => :environment do |_, args|
    term_uid = args[:term_uid]
    raise "Usage: rake catalog:sync_calendars[term_uid]" unless term_uid

    term = Term.find_by_uid!(term_uid)

    users = User.joins(:enrollments)
                .where(enrollments: { term_id: term.id })
                .joins(:oauth_credentials)
                .where.not(oauth_credentials: { id: nil })
                .distinct

    puts "Queueing calendar syncs for #{users.count} users in term #{term.name}..."

    users.find_each do |user|
      CourseCalendars::SyncJob.perform_bulk_later(user)
      puts "  Queued sync for user #{user.id} (#{user.email})"
    end

    puts "Done! Syncs queued for processing."
  end
end
