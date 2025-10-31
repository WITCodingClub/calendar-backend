# lib/tasks/migrate_calendars.rake
namespace :google_calendar do
  desc "Migrate user-owned calendars to service account ownership"
  task migrate_to_service_account: :environment do
    # Force reload of classes in development
    Rails.application.eager_load! if Rails.env.development?

    User.where.not(google_course_calendar_id: nil).find_each do |user|
      begin
        puts "Migrating calendar for #{user.email}..."

        # Store old calendar ID
        old_calendar_id = user.google_course_calendar_id

        # Skip if no Google tokens
        if user.google_access_token.blank?
          puts "⚠️  Skipping #{user.email} - no Google access token"
          next
        end

        # Clear the stored ID to force recreation
        user.update!(google_course_calendar_id: nil)

        # Create new service-account-owned calendar
        new_calendar_id = user.create_or_get_course_calendar

        puts "  Created new calendar: #{new_calendar_id}"

        # Copy events from old to new
        begin
          service = GoogleCalendarService.new(user)
          service_account_service = service.send(:service_account_calendar_service)
          user_calendar_service = service.send(:user_calendar_service)

          # List all events from old calendar
          events_response = user_calendar_service.list_events(old_calendar_id)

          if events_response.items && events_response.items.any?
            puts "  Copying #{events_response.items.size} events..."
            events_response.items.each do |event|
              # Create a new event object with only the necessary fields
              new_event = Google::Apis::CalendarV3::Event.new(
                summary: event.summary,
                description: event.description,
                location: event.location,
                start: event.start,
                end: event.end,
                recurrence: event.recurrence,
                attendees: event.attendees,
                color_id: event.color_id
              )
              service_account_service.insert_event(new_calendar_id, new_event)
            end
          end
        rescue => e
          puts "  ⚠️  Could not copy events: #{e.message}"
        end

        # Try to delete old calendar (user might not have permission)
        begin
          user_calendar_service = GoogleCalendarService.new(user).send(:user_calendar_service)
          user_calendar_service.delete_calendar(old_calendar_id)
          puts "  Deleted old calendar"
        rescue => e
          puts "  ⚠️  Could not delete old calendar (user may need to do this manually): #{e.message}"
        end

        puts "✓ Migrated #{user.email}"
      rescue => e
        puts "✗ Failed for #{user.email}: #{e.message}"
        puts "  #{e.backtrace.first(3).join("\n  ")}" if Rails.env.development?
      end
    end
  end
end
