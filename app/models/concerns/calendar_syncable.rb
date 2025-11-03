module CalendarSyncable
  extend ActiveSupport::Concern

  included do
    # Mark user's calendar as needing sync after enrollment changes
    after_save :mark_user_calendar_for_sync
    after_destroy :mark_user_calendar_for_sync
  end

  private

  def mark_user_calendar_for_sync
    # Only mark if the user has a Google Calendar set up
    return unless user&.google_course_calendar_id.present?

    user.update_column(:calendar_needs_sync, true)
  end
end
