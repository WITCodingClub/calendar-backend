# frozen_string_literal: true

# Cleans up orphaned GoogleCalendarEvent records
# Orphaned events have no associated meeting_time, final_exam, or university_calendar_event
# This can happen when:
# - Courses are deleted during catalog refresh
# - Meeting times are removed
# - The import process orphans records
class CleanupOrphanedCalendarEventsJob < ApplicationJob
  queue_as :default

  def perform(dry_run: false)
    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Starting orphaned calendar event cleanup (dry_run: #{dry_run})"

    orphaned_events = GoogleCalendarEvent.orphaned
    total_count = orphaned_events.count

    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Found #{total_count} orphaned events"

    return { total: total_count, deleted: 0, errors: 0 } if dry_run || total_count.zero?

    deleted_count = 0
    error_count = 0

    # Group by calendar for efficient API calls
    orphaned_events.includes(:google_calendar, google_calendar: :oauth_credential).find_each do |event|
      begin
        delete_orphaned_event(event)
        deleted_count += 1
      rescue => e
        Rails.logger.error "[CleanupOrphanedCalendarEventsJob] Error deleting event #{event.id}: #{e.message}"
        error_count += 1
      end
    end

    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Completed: deleted #{deleted_count}, errors #{error_count}"

    { total: total_count, deleted: deleted_count, errors: error_count }
  end

  private

  def delete_orphaned_event(event)
    calendar = event.google_calendar
    credential = calendar&.oauth_credential

    # Try to delete from Google Calendar if we have credentials
    if credential && calendar.google_calendar_id.present?
      begin
        service = build_calendar_service(credential)
        service.delete_event(calendar.google_calendar_id, event.google_event_id)
        Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Deleted event #{event.google_event_id} from Google Calendar"
      rescue Google::Apis::ClientError => e
        # Event may already be deleted in Google Calendar (404), that's fine
        if e.status_code == 404
          Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Event #{event.google_event_id} already deleted from Google Calendar"
        else
          Rails.logger.warn "[CleanupOrphanedCalendarEventsJob] Failed to delete event #{event.google_event_id} from Google: #{e.message}"
        end
      end
    end

    # Always delete from database
    event.destroy!
    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Deleted event #{event.id} from database"
  end

  def build_calendar_service(credential)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = build_google_authorization(credential)
    service
  end

  def build_google_authorization(credential)
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at: credential.token_expires_at
    )

    # Refresh if needed
    if credential.token_expires_at && credential.token_expires_at < Time.current
      credentials.refresh!
      credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.zone.at(credentials.expires_at)
      )
    end

    credentials
  end

end
