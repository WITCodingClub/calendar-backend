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
  # It shares the concurrency group and key of CourseCalendars::SyncJob, like
  # FriendMeetings::PublishJob, so it never runs at the same time as a publish or
  # a sync for the same person.
  class RemoveJob < ApplicationJob
    queue_as :high

    limits_concurrency to: 1, group: CourseCalendars::SyncJob::CONCURRENCY_GROUP,
                       key: ->(meeting) { "google_calendar_sync_user_#{meeting.user_id}" }

    retry_on MicrosoftGraph::Error, Google::Apis::ServerError, Google::Apis::RateLimitError,
             Google::Apis::TransmissionError, Google::Apis::ClientError,
             wait: :polynomially_longer, attempts: 8
    discard_on ActiveJob::DeserializationError

    def perform(meeting)
      return unless meeting.cancelled?

      FriendMeetings::Publisher.new(meeting.user).remove(meeting)
    end
  end
end
