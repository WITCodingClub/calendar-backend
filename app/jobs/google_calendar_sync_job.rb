# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  def perform(user, force: false)
    # Skip if no course schedule changes since last sync
    unless force
      last_sync = user.google_calendars.maximum(:updated_at)
      last_course_update = user.courses.maximum(:updated_at)
      
      if last_sync.present? && last_course_update.present? && 
         last_sync > last_course_update
        Rails.logger.info "Skipping sync for user #{user.id} - no changes since #{last_sync}"
        return
      end
    end
    
    user.sync_course_schedule(force: force)
  end

end
