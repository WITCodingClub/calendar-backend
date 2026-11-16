# frozen_string_literal: true

namespace :calendar do
  desc "Force a sync of every user with a course calendar, on any provider"
  task force_sync_all: :environment do
    users = CourseCalendars::ResyncAudience.all
    puts "Queuing forced calendar syncs for #{users.count} users..."
    batch = CourseCalendars::SyncJob.perform_bulk_in_batch(users, reason: "manual", force: true)
    puts "Queued as batch #{batch.id}"
  end

  desc "Force a sync of one user's calendars, by email"
  task :force_sync_user, [ :email ] => :environment do |_t, args|
    abort "Usage: rails calendar:force_sync_user[user@example.com]" if args[:email].blank?

    user = User.find_by(email: args[:email]) || abort("User not found with email: #{args[:email]}")
    abort "User has no calendar that syncs" unless CourseCalendars.resync(user, force: true)

    puts "Queued a forced calendar sync for #{user.email}"
  end

  desc "Force a sync of one user's calendars, by id"
  task :force_sync_user_id, [ :user_id ] => :environment do |_t, args|
    abort "Usage: rails calendar:force_sync_user_id[123]" if args[:user_id].blank?

    user = User.find_by(id: args[:user_id]) || abort("User not found with ID: #{args[:user_id]}")
    abort "User has no calendar that syncs" unless CourseCalendars.resync(user, force: true)

    puts "Queued a forced calendar sync for user #{user.id}"
  end

  desc "Show calendar sync statistics"
  task sync_stats: :environment do
    with_calendar = User.with_course_calendar

    puts "Calendar Sync Statistics:"
    puts "=" * 40
    puts "Total users:                     #{User.count}"
    CourseCalendar.group(:provider).count.each do |provider, count|
      puts "#{"#{provider.capitalize} calendars:".ljust(32)} #{count}"
    end
    puts "Users marked as needing sync:    #{User.needs_sync.count}"
    puts "Users synced in last 24 hours:   #{User.where(last_calendar_sync_at: 24.hours.ago..).count}"

    oldest_sync = User.minimum(:last_calendar_sync_at)
    puts "Oldest sync:                     #{oldest_sync&.strftime('%Y-%m-%d %H:%M:%S') || 'none'}"
    puts "With calendars but never synced: #{with_calendar.where(last_calendar_sync_at: nil).count}"
    puts "=" * 40
  end
end
