# frozen_string_literal: true

module FriendMeetings
  # Writes a changed FriendMeeting to its provider events, and makes each event
  # that is missing. The owner's edit and an unfriend both start it.
  #
  # It takes CourseCalendars::UserLock, so it never runs at the same time as a publish or
  # a sync for the same person.
  class UpdateJob < ApplicationJob
    include CourseCalendars::UserLock
    include CourseCalendars::ProviderRetries

    queue_as :high

    limits_concurrency_per_user(&:user_id)

    retry_on_provider_errors
    discard_on_auth_errors

    def perform(meeting)
      FriendMeetings::Publisher.new(meeting.user).update(meeting)
    end
  end
end
