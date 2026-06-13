# frozen_string_literal: true

namespace :calendar do
  desc "Fix duplicate Google Calendar events"
  task fix_duplicates: :environment do
    puts "Starting duplicate calendar event cleanup..."

    fixed_users           = 0
    total_duplicates_removed = 0

    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 50) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar

        puts "Processing user #{user.id} (#{user.email})..."

        all_events      = calendar.google_calendar_events.to_a
        existing_events = {}
        duplicates      = []

        all_events.each do |e|
          key = if e.meeting_time_id
                  "mt_#{e.meeting_time_id}"
                elsif e.final_exam_id
                  "fe_#{e.final_exam_id}"
                else
                  "ue_#{e.university_calendar_event_id}"
                end

          if existing_events[key]
            if e.created_at > existing_events[key].created_at
              duplicates << existing_events[key]
              existing_events[key] = e
            else
              duplicates << e
            end
          else
            existing_events[key] = e
          end
        end

        if duplicates.any?
          puts "  Found #{duplicates.size} duplicate events to remove"
          fixed_users += 1
          service = GoogleCalendarService.new(user)

          duplicates.each do |cal_event|
            begin
              user_service = service.send(:user_calendar_service)
              user_service.delete_event(calendar.google_calendar_id, cal_event.google_event_id)
              cal_event.destroy
              total_duplicates_removed += 1
              print "."
            rescue Google::Apis::ClientError => e
              if e.status_code == 404
                cal_event.destroy
                total_duplicates_removed += 1
                print "x"
              else
                puts "\n  Error deleting event #{cal_event.id}: #{e.message}"
              end
            rescue => e
              puts "\n  Error deleting event #{cal_event.id}: #{e.message}"
            end
          end
          puts
        end

        if user.enrollments.any?
          begin
            puts "  Triggering calendar resync..."
            GoogleCalendarSyncJob.perform_later(user, force: true)
          rescue => e
            puts "  Error queueing sync job: #{e.message}"
          end
        end
      end
    end

    puts "\n=== Cleanup Complete ==="
    puts "Users fixed:             #{fixed_users}"
    puts "Duplicate events removed: #{total_duplicates_removed}"
  end

  desc "Dry run to check for duplicate events"
  task check_duplicates: :environment do
    puts "Checking for duplicate calendar events..."

    users_with_duplicates = 0
    total_duplicates      = 0
    tbd_locations         = 0

    User.joins(oauth_credentials: :google_calendar).find_in_batches(batch_size: 50) do |users|
      users.each do |user|
        calendar = user.google_credential&.google_calendar
        next unless calendar

        duplicates = calendar.google_calendar_events
                             .where.not(meeting_time_id: nil)
                             .group(:meeting_time_id)
                             .having("count(*) > 1")
                             .count

        if duplicates.any?
          users_with_duplicates += 1
          extra = duplicates.values.sum - duplicates.size
          total_duplicates += extra
          puts "User #{user.id}: #{extra} duplicate events across #{duplicates.size} meeting times"
        end

        tbd_count = calendar.google_calendar_events.where("location ILIKE ?", "%TBD%").count
        if tbd_count > 0
          tbd_locations += tbd_count
          puts "User #{user.id}: #{tbd_count} events with TBD locations"
        end
      end
    end

    puts "\n=== Summary ==="
    puts "Users with duplicates: #{users_with_duplicates}"
    puts "Total duplicate events: #{total_duplicates}"
    puts "Total TBD locations:    #{tbd_locations}"
  end
end
