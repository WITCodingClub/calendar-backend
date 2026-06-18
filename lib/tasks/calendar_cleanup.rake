# frozen_string_literal: true

namespace :calendar do
  desc "List all orphaned calendars (exist in Google but not in database)"
  task list_orphaned_calendars: :environment do
    puts "Finding orphaned calendars...\n"

    service         = GoogleCalendarService.new
    google_calendars = service.list_calendars
    db_calendar_ids = GoogleCalendar.pluck(:google_calendar_id)

    puts "Calendars in Google:    #{google_calendars.items.count}"
    puts "Calendars in database:  #{db_calendar_ids.count}\n\n"

    orphaned = google_calendars.items.reject { |cal| db_calendar_ids.include?(cal.id) }

    orphaned.each do |cal|
      puts "  #{cal.summary}"
      puts "     ID: #{cal.id}"
      puts "     ---"
    end

    puts "\n#{orphaned.count} orphaned calendar(s) found"
  end

  desc "Delete all orphaned calendars from Google"
  task cleanup_orphaned_calendars: :environment do
    puts "Finding orphaned calendars...\n"

    service         = GoogleCalendarService.new
    google_calendars = service.list_calendars
    db_calendar_ids = GoogleCalendar.pluck(:google_calendar_id)

    orphaned = google_calendars.items.reject { |cal| db_calendar_ids.include?(cal.id) }
    puts "Found #{orphaned.count} orphaned calendar(s)\n\n"

    orphaned.each do |cal|
      puts "Deleting: #{cal.summary} (ID: #{cal.id})"
      begin
        service.delete_calendar(cal.id)
        puts "  Successfully deleted"
      rescue Google::Apis::ClientError => e
        puts "  Failed to delete: #{e.message}"
      rescue => e
        puts "  Error: #{e.message}"
      end
      puts ""
    end

    puts "Cleanup complete!"
  end

  desc "Sync finals for a specific term to all users' calendars (retroactive)"
  task :sync_finals_for_term, [ :year, :season ] => :environment do |_t, args|
    unless args[:year] && args[:season]
      puts "Usage: rails calendar:sync_finals_for_term[2025,fall]"
      puts "Seasons: spring, summer, fall"
      exit 1
    end

    year   = args[:year].to_i
    season = args[:season].to_sym

    term = Term.find_by(year: year, season: season)
    unless term
      puts "Term not found: #{season.to_s.capitalize} #{year}"
      exit 1
    end

    puts "Syncing finals for #{term.name}..."

    users_with_calendars = User.joins(oauth_credentials: :google_calendar)
                               .where(oauth_credentials: { provider: "google" })
                               .distinct

    puts "Found #{users_with_calendars.count} users with calendars\n\n"

    synced_count  = 0
    skipped_count = 0
    error_count   = 0

    users_with_calendars.find_each do |user|
      enrolled_course_ids = user.enrollments.joins(:course)
                                .where(courses: { term_id: term.id })
                                .pluck(:course_id)

      if enrolled_course_ids.empty?
        skipped_count += 1
        next
      end

      finals_events = FinalExam.where(course_id: enrolled_course_ids)
                               .includes(course: :faculties)
                               .filter_map do |final_exam|
        next unless final_exam.start_datetime && final_exam.end_datetime

        {
          summary:       "Final Exam: #{final_exam.course_title}",
          description:   final_exam.course_code,
          location:      final_exam.location,
          start_time:    final_exam.start_datetime,
          end_time:      final_exam.end_datetime,
          course_code:   final_exam.course_code,
          final_exam_id: final_exam.id,
          recurrence:    nil
        }
      end

      if finals_events.empty?
        skipped_count += 1
        next
      end

      begin
        puts "  Processing #{finals_events.count} finals for User #{user.id}..."
        service = GoogleCalendarService.new(user)
        service.update_specific_events(finals_events, force: true)
        puts "✓ User #{user.id} (#{user.email}): Synced #{finals_events.count} finals"
        synced_count += 1
      rescue Signet::AuthorizationError
        puts "  User #{user.id} (#{user.email}): OAuth expired — user needs to re-authenticate"
        error_count += 1
      rescue => e
        puts "✗ User #{user.id} (#{user.email}): #{e.class.name} - #{e.message}"
        error_count += 1
      end
    end

    puts ""
    puts "Sync complete!"
    puts "  Synced:  #{synced_count} users"
    puts "  Skipped: #{skipped_count} users (no enrollments or finals)"
    puts "  Errors:  #{error_count} users"
  end

  desc "Force sync all calendars for all users"
  task force_sync_all: :environment do
    puts "Force syncing all user calendars..."

    users_with_calendars = User.joins(oauth_credentials: :google_calendar)
                               .where(oauth_credentials: { provider: "google" })
                               .distinct

    puts "Found #{users_with_calendars.count} users with calendars\n\n"

    synced_count = 0
    error_count  = 0

    users_with_calendars.find_each do |user|
      begin
        user.sync_course_schedule(force: true)
        puts "✓ User #{user.id} (#{user.email}): Synced"
        synced_count += 1
      rescue => e
        puts "✗ User #{user.id} (#{user.email}): #{e.message}"
        error_count += 1
      end
    end

    puts ""
    puts "Sync complete!"
    puts "  Synced: #{synced_count} users"
    puts "  Errors: #{error_count} users"
  end
end
