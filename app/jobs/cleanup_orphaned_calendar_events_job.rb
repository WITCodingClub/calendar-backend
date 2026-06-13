# frozen_string_literal: true

# Cleans up orphaned GoogleCalendarEvent records — events with no associated
# meeting_time, final_exam, or university_calendar_event. Can happen when courses
# are deleted during catalog refresh or meeting times are removed.
class CleanupOrphanedCalendarEventsJob < ApplicationJob
  queue_as :low

  def perform(dry_run: false)
    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Starting (dry_run: #{dry_run})"

    orphaned_events = GoogleCalendarEvent.orphaned
    total_count = orphaned_events.count

    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Found #{total_count} orphaned events"

    return { total: total_count, deleted: 0, errors: 0 } if dry_run || total_count.zero?

    deleted_count = 0
    error_count = 0

    orphaned_events.includes(:google_calendar, google_calendar: :oauth_credential).find_each do |event|
      delete_orphaned_event(event)
      deleted_count += 1
    rescue => e
      Rails.logger.error "[CleanupOrphanedCalendarEventsJob] Error deleting event #{event.id}: #{e.message}"
      error_count += 1
    end

    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Completed: deleted #{deleted_count}, errors #{error_count}"

    { total: total_count, deleted: deleted_count, errors: error_count }
  end

  private

  def delete_orphaned_event(event)
    calendar = event.google_calendar
    credential = calendar&.oauth_credential

    if credential && calendar.google_calendar_id.present?
      begin
        service = build_calendar_service(credential)
        service.delete_event(calendar.google_calendar_id, event.google_event_id)
        Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Deleted event #{event.google_event_id} from Google Calendar"
      rescue Google::Apis::ClientError => e
        if e.status_code == 404
          Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Event #{event.google_event_id} already deleted from Google Calendar"
        else
          Rails.logger.warn "[CleanupOrphanedCalendarEventsJob] Failed to delete event #{event.google_event_id} from Google: #{e.message}"
        end
      end
    end

    event.destroy!
    Rails.logger.info "[CleanupOrphanedCalendarEventsJob] Deleted event #{event.id} from database"
  end

  def build_calendar_service(credential)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = build_google_authorization(credential)
    service
  end

  def build_google_authorization(credential)
    creds = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: [ "https://www.googleapis.com/auth/calendar" ],
      access_token: credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at: credential.token_expires_at
    )

    if credential.token_expires_at && credential.token_expires_at < Time.current
      creds.refresh!
      credential.update!(
        access_token: creds.access_token,
        token_expires_at: Time.zone.at(creds.expires_at)
      )
    end

    creds
  end
end
