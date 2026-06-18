# frozen_string_literal: true

namespace :calendar do
  desc "Emergency: Force resync calendar for a specific user or all users"
  task :emergency_resync, [ :user_id ] => :environment do |_t, args|
    if args[:user_id]
      user = User.find(args[:user_id])
      puts "Emergency resync for user #{user.id} (#{user.email})..."

      if user.google_credential&.google_calendar
        puts "Clearing database records..."
        user.google_credential.google_calendar.google_calendar_events.destroy_all
      end

      puts "Triggering full calendar rebuild..."
      GoogleCalendarSyncJob.perform_now(user, force: true)
      puts "Done! Calendar should be restored."
    else
      puts "Emergency resync for ALL users..."
      User.joins(oauth_credentials: :google_calendar).find_each do |user|
        puts "Resyncing user #{user.id}..."
        GoogleCalendarSyncJob.perform_later(user, force: true)
      end
      puts "All sync jobs queued!"
    end
  end
end
