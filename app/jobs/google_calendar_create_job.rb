# frozen_string_literal: true

class GoogleCalendarCreateJob < ApplicationJob
  queue_as :high

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    # Use advisory lock to prevent race condition when multiple OAuth credentials
    # are added quickly - both would try to create calendars simultaneously
    user.with_lock do
      # Re-check inside lock to prevent duplicate calendar creation
      existing_calendar = GoogleCalendar.for_user(user).first
      if existing_calendar
        Rails.logger.info "[GoogleCalendarCreateJob] Calendar already exists for user #{user_id}, skipping creation"
        # Still share with any new OAuth credentials
        GoogleCalendarService.new(user).send(:share_calendar_with_user, existing_calendar.google_calendar_id)
        GoogleCalendarService.new(user).send(:add_calendar_to_all_oauth_users, existing_calendar.google_calendar_id)
      else
        # Create or get the calendar
        GoogleCalendarService.new(user).create_or_get_course_calendar
      end
    end

    # Automatically sync events after calendar creation (outside lock)
    user.sync_course_schedule(force: true)
  end

end
