# frozen_string_literal: true

namespace :calendar do
  desc "Force sync calendars for all users"
  task force_sync_all: :environment do
    puts "Running forced calendar sync for all users..."

    total_users   = User.count
    queued_count  = 0
    skipped_count = 0

    User.find_each.with_index do |user, index|
      if user.google_credential&.google_calendar
        puts "#{index + 1}/#{total_users}: Queuing sync for user #{user.id} (#{user.email})"
        GoogleCalendarSyncJob.perform_later(user, force: true)
        queued_count += 1
      else
        puts "#{index + 1}/#{total_users}: Skipping user #{user.id} (no Google Calendar setup)"
        skipped_count += 1
      end
    end

    puts "\n" + "=" * 50
    puts "SUMMARY:"
    puts "Total users:        #{total_users}"
    puts "Sync jobs queued:   #{queued_count}"
    puts "Skipped:            #{skipped_count}"
    puts "=" * 50
  end

  desc "Force sync calendar for a specific user by email"
  task :force_sync_user, [:email] => :environment do |_t, args|
    if args[:email].blank?
      puts "Usage: rails calendar:force_sync_user[user@example.com]"
      exit 1
    end

    user = User.find_by(email: args[:email])
    if user.nil?
      puts "User not found with email: #{args[:email]}"
      exit 1
    end

    if user.google_credential&.google_calendar
      puts "Queuing forced calendar sync for #{user.email}..."
      GoogleCalendarSyncJob.perform_later(user, force: true)
      puts "✓ Sync job queued successfully"
    else
      puts "✗ User has no Google Calendar setup"
      exit 1
    end
  end

  desc "Force sync calendar for a specific user by ID"
  task :force_sync_user_id, [:user_id] => :environment do |_t, args|
    if args[:user_id].blank?
      puts "Usage: rails calendar:force_sync_user_id[123]"
      exit 1
    end

    user = User.find_by(id: args[:user_id])
    if user.nil?
      puts "User not found with ID: #{args[:user_id]}"
      exit 1
    end

    if user.google_credential&.google_calendar
      puts "Queuing forced calendar sync for user #{user.id} (#{user.email})..."
      GoogleCalendarSyncJob.perform_later(user, force: true)
      puts "✓ Sync job queued successfully"
    else
      puts "✗ User has no Google Calendar setup"
      exit 1
    end
  end

  desc "Show calendar sync statistics"
  task sync_stats: :environment do
    puts "Calendar Sync Statistics:"
    puts "=" * 40

    puts "Total users:                    #{User.count}"
    puts "Users with Google Calendars:    #{User.joins(:google_calendars).distinct.count}"
    puts "Users marked as needing sync:   #{User.where(calendar_needs_sync: true).count}"

    recent_syncs = User.where.not(last_calendar_sync_at: nil)
                       .where("last_calendar_sync_at > ?", 24.hours.ago)
                       .count
    puts "Users synced in last 24 hours:  #{recent_syncs}"

    oldest_sync = User.where.not(last_calendar_sync_at: nil).minimum(:last_calendar_sync_at)
    puts "Oldest sync:                    #{oldest_sync&.strftime('%Y-%m-%d %H:%M:%S') || 'none'}"

    never_synced = User.joins(:google_calendars).where(last_calendar_sync_at: nil).count
    puts "With calendars but never synced: #{never_synced}"

    puts "=" * 40
  end
end
