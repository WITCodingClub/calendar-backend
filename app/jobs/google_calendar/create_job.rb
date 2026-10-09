# frozen_string_literal: true

module GoogleCalendar
  class CreateJob < ApplicationJob
    queue_as :high

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      user.with_lock do
        existing_calendar = CourseCalendar.google.for_user(user).first
        if existing_calendar
          Rails.logger.info "[GoogleCalendar::CreateJob] Calendar already exists for user #{user_id}, skipping creation"
          service = GoogleCalendar::Provider.new(user)
          service.send(:share_calendar_with_user, existing_calendar.external_calendar_id)
          service.send(:add_calendar_to_all_oauth_users, existing_calendar.external_calendar_id)
        else
          GoogleCalendar::Provider.new(user).create_or_get_course_calendar
        end
      end

      # Route the follow-up sync through CourseCalendars::SyncJob rather than syncing
      # inline: that job carries limits_concurrency keyed per user, so a
      # creation-triggered sync can't race a concurrent sync and double-create
      # remote events.
      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
