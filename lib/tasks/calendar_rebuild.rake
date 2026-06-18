# frozen_string_literal: true

namespace :calendars do
  desc "Delete all user Google calendars"
  task delete_all: :environment do
    puts "Starting calendar deletion process..."

    calendars     = GoogleCalendar.includes(:oauth_credential)
    total         = calendars.count

    if total.zero?
      puts "No calendars found to delete"
      exit
    end

    puts "Found #{total} calendars to delete"

    if Rails.env.production?
      print "You are about to delete #{total} calendars in PRODUCTION. Type 'DELETE' to confirm: "
      exit unless STDIN.gets.chomp == "DELETE"
    end

    deleted_count = 0
    error_count   = 0

    calendars.find_each do |calendar|
      user_email = calendar.oauth_credential&.user&.email || "unknown"
      puts "Deleting calendar for user: #{user_email} (Calendar ID: #{calendar.google_calendar_id})"

      begin
        GoogleCalendarService.new(calendar.oauth_credential.user).delete_calendar(calendar.google_calendar_id)
        calendar.google_calendar_events.destroy_all
        calendar.destroy!
        deleted_count += 1
        puts "  Successfully deleted calendar for #{user_email}"
      rescue => e
        error_count += 1
        puts "  Failed to delete calendar for #{user_email}: #{e.message}"
        begin
          calendar.google_calendar_events.destroy_all
          calendar.destroy!
          puts "  Cleaned up local records for #{user_email}"
        rescue => local_error
          puts "  Failed to clean up local records: #{local_error.message}"
        end
      end

      sleep 0.1
    end

    puts "\nSummary:"
    puts "Total processed:      #{total}"
    puts "Successfully deleted: #{deleted_count}"
    puts "Errors:               #{error_count}"
  end

  desc "Recreate Google calendars for all users with OAuth credentials"
  task recreate_all: :environment do
    puts "Starting calendar recreation process..."

    credentials  = OauthCredential.where(provider: "google").joins(:user).where.not(access_token: [ nil, "" ])
    total        = credentials.count

    if total.zero?
      puts "No OAuth credentials found"
      exit
    end

    puts "Found #{total} OAuth credentials to process"

    created_count = 0
    error_count   = 0
    skipped_count = 0

    credentials.find_each do |credential|
      user       = credential.user
      user_email = user.email || "unknown"

      if credential.google_calendar.present?
        puts "Calendar already exists for #{user_email}, skipping"
        skipped_count += 1
        next
      end

      puts "Creating calendar for user: #{user_email}"

      begin
        service     = GoogleCalendarService.new(user)
        calendar_id = service.create_or_get_course_calendar

        if calendar_id
          puts "  Successfully created calendar for #{user_email} (ID: #{calendar_id})"
          created_count += 1
        else
          puts "  Failed to create calendar for #{user_email}"
          error_count += 1
        end
      rescue => e
        error_count += 1
        puts "  Error processing #{user_email}: #{e.message}"
      end

      sleep 0.1
    end

    puts "\nSummary:"
    puts "Total processed:            #{total}"
    puts "Successfully created:       #{created_count}"
    puts "Skipped (already exists):   #{skipped_count}"
    puts "Errors:                     #{error_count}"
  end

  desc "Delete and recreate all user Google calendars"
  task rebuild_all: :environment do
    puts "Starting complete calendar rebuild process..."
    Rake::Task["calendars:delete_all"].invoke
    puts "\nWaiting 5 seconds before recreation..."
    sleep 5
    Rake::Task["calendars:recreate_all"].invoke
    puts "\nComplete calendar rebuild finished!"
  end
end
