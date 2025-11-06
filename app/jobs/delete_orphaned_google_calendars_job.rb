# frozen_string_literal: true

class DeleteOrphanedGoogleCalendarsJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[DeleteOrphanedGoogleCalendarsJob] Starting orphaned calendar cleanup"

    deleted_count = 0
    error_count = 0

    # Find all calendars and check their status
    all_calendar_ids = GoogleCalendar.pluck(:id)
    orphaned_calendar_ids = []

    # Find calendars with missing oauth credentials
    orphaned_by_credential = GoogleCalendar.where.missing(:oauth_credential)
                                           
                                           .pluck(:id)
    orphaned_calendar_ids.concat(orphaned_by_credential)

    # Find calendars with expired credentials that cannot be refreshed
    orphaned_by_expired_token = GoogleCalendar.joins(:oauth_credential)
                                              .where(oauth_credentials: { token_expires_at: ..Time.current })
                                              .where(oauth_credentials: { refresh_token: nil })
                                              .pluck(:id)
    orphaned_calendar_ids.concat(orphaned_by_expired_token)

    # Find calendars whose oauth credential has no user
    orphaned_by_user_sql = <<-SQL.squish
      SELECT google_calendars.id
      FROM google_calendars
      INNER JOIN oauth_credentials ON oauth_credentials.id = google_calendars.oauth_credential_id
      LEFT OUTER JOIN users ON users.id = oauth_credentials.user_id
      WHERE users.id IS NULL
    SQL
    orphaned_by_user = ActiveRecord::Base.connection.execute(orphaned_by_user_sql).to_a.pluck("id")
    orphaned_calendar_ids.concat(orphaned_by_user)

    # Get unique calendar objects with eager loaded associations
    orphaned_calendars = GoogleCalendar.where(id: orphaned_calendar_ids.uniq)
                                       .includes(:oauth_credential)

    Rails.logger.info "[DeleteOrphanedGoogleCalendarsJob] Found #{orphaned_calendars.size} orphaned calendars"

    orphaned_calendars.each do |calendar|
      begin
        reason = determine_orphan_reason(calendar)
        Rails.logger.info "[DeleteOrphanedGoogleCalendarsJob] Deleting calendar #{calendar.id} " \
                          "(google_calendar_id: #{calendar.google_calendar_id}) - Reason: #{reason}"

        calendar.destroy!
        deleted_count += 1
      rescue => e
        error_count += 1
        Rails.logger.error "[DeleteOrphanedGoogleCalendarsJob] Failed to delete calendar #{calendar.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    Rails.logger.info "[DeleteOrphanedGoogleCalendarsJob] Completed: " \
                      "#{deleted_count} deleted, #{error_count} errors"

    { deleted: deleted_count, errors: error_count }
  end

  private

  def determine_orphan_reason(calendar)
    return "Missing OAuth credential" if calendar.oauth_credential.blank?

    credential = calendar.oauth_credential

    return "Missing user" unless credential.user_id.present? && User.exists?(credential.user_id)

    if credential.token_expires_at.present? &&
       credential.token_expires_at <= Time.current &&
       credential.refresh_token.blank?
      return "Expired token without refresh capability"
    end

    "Unknown reason"
  end

end
