# frozen_string_literal: true

module Cleanup
  # Cleans up orphaned CalendarEvent records — events with no associated
  # meeting_time, final_exam, or university_calendar_event. Can happen when courses
  # are deleted during catalog refresh or meeting times are removed.
  class OrphanedCalendarEventsJob < ApplicationJob
    queue_as :low

    def perform(dry_run: false)
      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Starting (dry_run: #{dry_run})"

      orphaned_events = CalendarEvent.orphaned
      total_count = orphaned_events.count

      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Found #{total_count} orphaned events"

      return { total: total_count, deleted: 0, errors: 0 } if dry_run || total_count.zero?

      deleted_count = 0
      error_count = 0

      orphaned_events.includes(:course_calendar, course_calendar: :oauth_credential).find_each do |event|
        delete_orphaned_event(event)
        deleted_count += 1
      rescue => e
        Rails.error.report(e, handled: true, context: { calendar_event_id: event.id })
        error_count += 1
      end

      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Completed: deleted #{deleted_count}, errors #{error_count}"

      { total: total_count, deleted: deleted_count, errors: error_count }
    end

    private

    def delete_orphaned_event(event)
      calendar   = event.course_calendar
      credential = calendar&.oauth_credential

      # A Microsoft row deletes its remote event from the destroy callback below.
      if calendar&.google? && credential && calendar.external_calendar_id.present?
        begin
          service = GoogleCalendar::CalendarServices.for_credential(credential)
          service.delete_event(calendar.external_calendar_id, event.external_event_id)
          Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Deleted event #{event.external_event_id} from Google Calendar"
        rescue Google::Apis::ClientError => e
          # Any other error keeps the row, so the next run tries the remote
          # event again. perform reports the error and counts it.
          raise unless GoogleCalendar::Provider.gone?(e)

          Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Event #{event.external_event_id} already deleted from Google Calendar"
        rescue Signet::AuthorizationError => e
          # Google refused the refresh token, so the remote event is out of
          # reach until the person connects again. Any other refusal, such as
          # invalid_client, keeps the row and perform reports it.
          raise unless OauthCredential.invalid_grant?(e)

          Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Google token revoked for credential #{credential.id}, so event #{event.external_event_id} stays on Google Calendar"
        end
      end

      event.destroy!
      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Deleted event #{event.id} from database"
    end
  end
end
