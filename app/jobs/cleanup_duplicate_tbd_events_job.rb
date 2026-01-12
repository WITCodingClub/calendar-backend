# frozen_string_literal: true

# This job cleans up duplicate events in Google Calendar where one has a TBD location
# and another has a valid location for the same meeting time.
class CleanupDuplicateTbdEventsJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    if user_id
      cleanup_for_user(User.find(user_id))
    else
      # Process all users with Google calendars
      User.joins(:google_calendars).distinct
          .find_each { |user| cleanup_for_user(user) }
    end
  end

  private

  def cleanup_for_user(user)
    Rails.logger.info "[CleanupDuplicateTbdEventsJob] Starting cleanup for user #{user.id}"

    google_calendar = user.google_credential&.google_calendar
    return unless google_calendar

    service = GoogleCalendarService.new(user)
    calendar_id = google_calendar.google_calendar_id

    # Get all calendar events for this user
    google_events = google_calendar.google_calendar_events
                                   .where.not(meeting_time_id: nil)
                                   .includes(meeting_time: [:building, :room])

    # Group events by meeting_time_id and recurrence pattern
    grouped_events = google_events.group_by do |event|
      mt = event.meeting_time
      next unless mt

      # Group by course, day, time to find duplicates
      [
        mt.course_id,
        mt.day_of_week,
        mt.begin_time,
        mt.end_time,
        mt.start_date,
        mt.end_date
      ]
    end

    events_deleted = 0

    grouped_events.each_value do |events|
      next if events.size <= 1 # No duplicates

      # Separate TBD and non-TBD events
      tbd_events = []
      valid_events = []

      events.each do |event|
        mt = event.meeting_time
        if tbd_location?(mt.building, mt.room)
          tbd_events << event
        else
          valid_events << event
        end
      end

      # If we have both TBD and valid events, delete the TBD ones
      next unless valid_events.any? && tbd_events.any?

      tbd_events.each do |event|
        begin
          # Delete from Google Calendar
          api_service = service.send(:user_calendar_service)
          api_service.delete_event(calendar_id, event.google_event_id)

          # Delete from database
          event.destroy!
          events_deleted += 1

          Rails.logger.info "[CleanupDuplicateTbdEventsJob] Deleted TBD duplicate event #{event.google_event_id} for user #{user.id}"
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            # Event already deleted from Google, just clean up database
            event.destroy!
            events_deleted += 1
          else
            Rails.logger.error "[CleanupDuplicateTbdEventsJob] Failed to delete event #{event.google_event_id}: #{e.message}"
          end
        end
      end
    end

    Rails.logger.info "[CleanupDuplicateTbdEventsJob] Completed cleanup for user #{user.id}. Deleted #{events_deleted} duplicate TBD events"
  rescue => e
    Rails.logger.error "[CleanupDuplicateTbdEventsJob] Error cleaning up for user #{user.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def tbd_location?(building, room)
    return true if building && tbd_building?(building)
    return true if room && tbd_room?(room)

    false
  end

  def tbd_building?(building)
    return false unless building

    # Empty/blank building means location not yet assigned (LeopardWeb sends null)
    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  def tbd_room?(room)
    return false unless room

    room.number == 0
    # Note: Room number is integer, not string
  end

end
