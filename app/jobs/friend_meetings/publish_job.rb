# frozen_string_literal: true

module FriendMeetings
  # Puts a new FriendMeeting in the person's provider calendars.
  #
  # It takes CourseCalendars::UserLock, so a publish and a sync for one person
  # never run at the same time. A retry skips each calendar that already has the
  # meeting.
  class PublishJob < ApplicationJob
    include CourseCalendars::UserLock
    include CourseCalendars::ProviderRetries

    queue_as :high

    limits_concurrency_per_user(&:user_id)

    retry_on_provider_errors
    discard_on_auth_errors

    def perform(meeting)
      FriendMeetings::Publisher.new(meeting.user).publish(meeting)
    end
  end
end
