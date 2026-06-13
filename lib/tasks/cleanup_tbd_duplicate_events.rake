# frozen_string_literal: true

namespace :calendar do
  desc "Clean up duplicate TBD events from Google Calendar using the service account"
  task cleanup_tbd_duplicate_events: :environment do
    puts "Starting cleanup of duplicate TBD events in Google Calendar..."
    puts "=" * 60

    service      = GoogleCalendarService.new
    calendar_svc = service.send(:service_account_calendar_service)

    users_with_calendars = User.joins(:google_calendars).distinct
    total                = users_with_calendars.count
    puts "Found #{total} users with calendars\n\n"

    fixed_users      = 0
    total_removed    = 0
    error_count      = 0

    users_with_calendars.find_each do |user|
      google_calendar = user.google_credential&.google_calendar
      next unless google_calendar

      calendar_id = google_calendar.google_calendar_id

      begin
        result = calendar_svc.list_events(
          calendar_id,
          single_events: true,
          max_results: 2500,
          order_by: "startTime",
          time_min: Time.current.iso8601
        )

        events_by_title = result.items.group_by(&:summary)
        user_removed    = 0

        events_by_title.each do |title, events|
          next if events.size <= 1

          tbd_events   = events.select { |e| e.location&.include?("TBD") || e.location&.include?("To Be Determined") }
          valid_events = events.reject { |e| e.location&.include?("TBD") || e.location&.include?("To Be Determined") }

          next unless valid_events.any? && tbd_events.any?

          tbd_events.each do |event|
            begin
              calendar_svc.delete_event(calendar_id, event.id)

              db_event = google_calendar.google_calendar_events.find_by(google_event_id: event.id)
              db_event&.destroy

              user_removed  += 1
              total_removed += 1
              print "."
            rescue Google::Apis::ClientError => e
              if e.status_code == 404
                db_event = google_calendar.google_calendar_events.find_by(google_event_id: event.id)
                db_event&.destroy
                user_removed  += 1
                total_removed += 1
                print "x"
              else
                error_count += 1
                print "E"
              end
            rescue => e
              error_count += 1
              Rails.logger.error "Failed to delete TBD event #{event.id}: #{e.message}"
              print "E"
            end
          end
        end

        if user_removed > 0
          puts "\n  User #{user.id} (#{user.email}): removed #{user_removed} TBD duplicates"
          fixed_users += 1
        end

        sleep 0.1
      rescue Google::Apis::RateLimitError
        puts "\n  User #{user.id}: Rate limited, sleeping 60s..."
        sleep 60
        retry
      rescue => e
        error_count += 1
        puts "\n  User #{user.id}: #{e.class.name} - #{e.message}"
      end
    end

    puts "\n\n=== Cleanup Complete ==="
    puts "Users with fixes:   #{fixed_users}"
    puts "Total events removed: #{total_removed}"
    puts "Errors:             #{error_count}"
  end
end
