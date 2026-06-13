# frozen_string_literal: true

class GoogleCalendarCreateJob < ApplicationJob
  queue_as :high

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    user.with_lock do
      existing_calendar = GoogleCalendar.for_user(user).first
      if existing_calendar
        Rails.logger.info "[GoogleCalendarCreateJob] Calendar already exists for user #{user_id}, skipping creation"
        service = GoogleCalendarService.new(user)
        service.send(:share_calendar_with_user, existing_calendar.google_calendar_id)
        service.send(:add_calendar_to_all_oauth_users, existing_calendar.google_calendar_id)
      else
        GoogleCalendarService.new(user).create_or_get_course_calendar
      end
    end

    user.sync_course_schedule(force: true)
  end
end
