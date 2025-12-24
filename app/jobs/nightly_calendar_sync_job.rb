# frozen_string_literal: true

class NightlyCalendarSyncJob < ApplicationJob
  queue_as :low

  def perform
    # Find all users who need their calendar synced
    # This includes users with calendar_needs_sync=true or have never been synced
    # Only sync users who have Google OAuth credentials with a course calendar ID set
    users_to_sync = User.joins(:oauth_credentials)
                        .where(oauth_credentials: { provider: "google" })
                        .where("oauth_credentials.metadata->>'course_calendar_id' IS NOT NULL")
                        .where(calendar_needs_sync: true)
                        .or(
                          User.joins(:oauth_credentials)
                              .where(oauth_credentials: { provider: "google" })
                              .where("oauth_credentials.metadata->>'course_calendar_id' IS NOT NULL")
                              .where(last_calendar_sync_at: nil)
                        )
                        .distinct

    Rails.logger.info "Nightly Calendar Sync: Processing #{users_to_sync.count} users"

    users_to_sync.find_each do |user|
      begin
        Rails.logger.info "Syncing calendar for user #{user.id}"

        # Perform the sync
        user.sync_course_schedule

        # Mark as synced
        user.update!(
          calendar_needs_sync: false,
          last_calendar_sync_at: Time.current
        )

        Rails.logger.info "Successfully synced calendar for user #{user.id}"
      rescue => e
        Rails.logger.error "Failed to sync calendar for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Continue with next user even if this one fails
      end
    end

    Rails.logger.info "Nightly Calendar Sync: Completed"
  end

end
