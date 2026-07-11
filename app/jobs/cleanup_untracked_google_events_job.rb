# frozen_string_literal: true

# Deletes events that exist in a user's Google Calendar but have no tracking
# row in google_calendar_events. These orphans were left behind when tracking
# rows were cascade-destroyed (e.g. meeting times destroyed on schedule
# re-upload) without deleting the real events, so every subsequent sync
# created a duplicate next to them.
#
# The app owns these calendars end-to-end, so any untracked event is one we
# created and lost the pointer to. Modified instances of a tracked recurring
# series are preserved (user-edited occurrences carry their own event id).
#
# Run with dry_run: true first to log what would be deleted without deleting.
class CleanupUntrackedGoogleEventsJob < ApplicationJob
  include GoogleApiRateLimiter

  queue_as :low

  def perform(google_calendar_id = nil, dry_run: false)
    calendars = if google_calendar_id
                  GoogleCalendar.where(id: google_calendar_id)
    else
                  GoogleCalendar.all
    end

    totals = { scanned: 0, deleted: 0, errors: 0 }

    calendars.find_each do |calendar|
      stats = reconcile_calendar(calendar, dry_run: dry_run)
      totals.each_key { |key| totals[key] += stats[key] }
    rescue => e
      totals[:errors] += 1
      Rails.logger.error "[CleanupUntrackedGoogleEventsJob] Failed for calendar #{calendar.id}: #{e.message}"
    end

    Rails.logger.info "[CleanupUntrackedGoogleEventsJob] Completed (dry_run: #{dry_run}): #{totals.to_json}"
    totals
  end

  private

  def reconcile_calendar(calendar, dry_run:)
    stats = { scanned: 0, deleted: 0, errors: 0 }
    tracked_ids = calendar.google_calendar_events.pluck(:google_event_id).to_set

    untracked = []
    page_token = nil

    loop do
      response = with_rate_limit_handling do
        calendar_service.list_events(
          calendar.google_calendar_id,
          max_results: 2500,
          page_token: page_token,
          show_deleted: false
        )
      end

      Array(response.items).each do |event|
        stats[:scanned] += 1
        next if event.status == "cancelled"
        next if tracked_ids.include?(event.id)
        # A user-edited occurrence of a tracked recurring series gets its own
        # event id; deleting it would wipe the user's edit.
        next if event.recurring_event_id.present? && tracked_ids.include?(event.recurring_event_id)

        untracked << event
      end

      page_token = response.next_page_token
      break if page_token.blank?
    end

    if dry_run
      untracked.each do |event|
        Rails.logger.info "[CleanupUntrackedGoogleEventsJob] [dry run] Would delete #{event.id} " \
                          "(#{event.summary.inspect}) from calendar #{calendar.id}"
      end
      stats[:deleted] = untracked.size
      return stats
    end

    with_batch_throttling(untracked) do |event|
      delete_untracked_event(calendar, event)
      stats[:deleted] += 1
    rescue Google::Apis::Error => e
      stats[:errors] += 1
      Rails.logger.error "[CleanupUntrackedGoogleEventsJob] Failed to delete #{event.id} " \
                         "from calendar #{calendar.id}: #{e.message}"
    end

    Rails.logger.info "[CleanupUntrackedGoogleEventsJob] Calendar #{calendar.id}: " \
                      "#{stats[:deleted]} untracked events deleted (#{stats[:scanned]} scanned)"
    stats
  end

  def delete_untracked_event(calendar, event)
    calendar_service.delete_event(calendar.google_calendar_id, event.id)
    Rails.logger.info "[CleanupUntrackedGoogleEventsJob] Deleted #{event.id} " \
                      "(#{event.summary.inspect}) from calendar #{calendar.id}"
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == 404
  end

  # The service account created and owns every app-managed calendar, so it can
  # list and delete regardless of the state of the user's OAuth tokens.
  def calendar_service
    @calendar_service ||= begin
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = service_account_credentials
      service
    end
  end

  def service_account_credentials
    service_account_config = Rails.application.credentials.dig(:google, :service_account)

    credentials_json = if service_account_config.is_a?(String)
                         service_account_config
    else
                         service_account_config.to_json
    end

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(credentials_json),
      scope:       Google::Apis::CalendarV3::AUTH_CALENDAR
    )
  end
end
