class NightlyCalendarSyncJob < ApplicationJob
  queue_as :low_priority

  def perform
    # Find all users who need their calendar synced
    # This includes users with calendar_needs_sync=true or have never been synced
    users_to_sync = User.where(calendar_needs_sync: true)
                        .or(User.where(last_calendar_sync_at: nil))
                        .where.not(google_course_calendar_id: nil)

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
      rescue StandardError => e
        Rails.logger.error "Failed to sync calendar for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Continue with next user even if this one fails
      end
    end

    Rails.logger.info "Nightly Calendar Sync: Completed"
  end
end
