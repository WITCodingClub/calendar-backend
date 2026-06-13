# frozen_string_literal: true

# Removes TBD-location duplicate events when a valid-location event exists for
# the same meeting time. Runs per-user or across all users with Google calendars.
class CleanupDuplicateTbdEventsJob < ApplicationJob
  queue_as :low

  def perform(user_id = nil)
    if user_id
      cleanup_for_user(User.find(user_id))
    else
      User.joins(:google_calendars).distinct
          .includes(oauth_credentials: :google_calendar)
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

    google_events = google_calendar.google_calendar_events
                                   .where.not(meeting_time_id: nil)
                                   .includes(meeting_time: { rooms: :building })

    grouped_events = google_events.group_by do |event|
      mt = event.meeting_time
      next unless mt

      [ mt.course_id, mt.day_of_week, mt.begin_time, mt.end_time, mt.start_date, mt.end_date ]
    end

    events_deleted = 0

    grouped_events.each_value do |events|
      next if events.size <= 1

      tbd_events   = events.select { |e| tbd_location?(e.meeting_time) }
      valid_events = events.reject { |e| tbd_location?(e.meeting_time) }

      next unless valid_events.any? && tbd_events.any?

      tbd_events.each do |event|
        begin
          api_service = service.send(:user_calendar_service)
          api_service.delete_event(calendar_id, event.google_event_id)
          event.destroy!
          events_deleted += 1
          Rails.logger.info "[CleanupDuplicateTbdEventsJob] Deleted TBD duplicate #{event.google_event_id} for user #{user.id}"
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            event.destroy!
            events_deleted += 1
          else
            Rails.logger.error "[CleanupDuplicateTbdEventsJob] Failed to delete #{event.google_event_id}: #{e.message}"
          end
        end
      end
    end

    Rails.logger.info "[CleanupDuplicateTbdEventsJob] Completed for user #{user.id}: #{events_deleted} events deleted"
  rescue => e
    Rails.logger.error "[CleanupDuplicateTbdEventsJob] Error for user #{user.id}: #{e.message}"
  end

  def tbd_location?(meeting_time)
    return false unless meeting_time

    tbd_building?(meeting_time.building) ||
      meeting_time.rooms.all? { |r| tbd_room?(r) }
  end

  def tbd_building?(building)
    return true if building.nil?

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name.downcase.include?("to be determined") ||
      building.name.downcase.include?("tbd") ||
      building.abbreviation.downcase == "tbd"
  end

  def tbd_room?(room)
    return true if room.nil?

    room.number.to_i.zero?
  end
end
