# frozen_string_literal: true

module FriendMeetings
  # Deletes the provider events of a FriendMeeting that its owner cancelled,
  # then the meeting. Until it is done, the meeting stays cancelled, so no sync
  # puts it back.
  #
  # Network, server, rate limit, and permission errors are retried with a
  # growing wait. When the retries run out, FriendMeetings::RemovalSweepJob starts
  # the job again every hour. A refused token never reaches the job:
  # FriendMeetings::Publisher#remove records it on the publication, and a
  # reconnect finishes the removal (OauthCredential#resume_friend_meetings).
  #
  # It takes CourseCalendars::UserLock, so it never runs at the same time as a publish or
  # a sync for the same person.
  class RemoveJob < ApplicationJob
    include CourseCalendars::UserLock
    include CourseCalendars::ProviderRetries

    queue_as :high

    limits_concurrency_per_user(&:user_id)

    retry_on_provider_errors Google::Apis::TransmissionError, Google::Apis::ClientError, attempts: 8

    def perform(meeting)
      return unless meeting.cancelled?

      FriendMeetings::Publisher.new(meeting.user).remove(meeting)
    end
  end
end
