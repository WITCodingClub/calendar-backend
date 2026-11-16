# frozen_string_literal: true

module GoogleCalendar
  class CreateJob < ApplicationJob
    include CourseCalendars::ProviderRetries

    queue_as :high

    retry_on_rate_limits

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      # A calendar that exists is shared again with each linked account.
      user.with_lock { GoogleCalendar::Provider.new(user).create_or_get_course_calendar }

      # CourseCalendars::SyncJob holds the per-user lock, so this sync cannot
      # race another one and create the same remote events twice.
      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
