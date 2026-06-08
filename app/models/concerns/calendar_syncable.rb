# frozen_string_literal: true

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
    return if user&.google_course_calendar_id.blank?

    # Using update_column to avoid triggering validations and callbacks in an after_save hook
    user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
  end
end
