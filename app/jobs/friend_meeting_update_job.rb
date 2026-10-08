# frozen_string_literal: true

# Writes a changed FriendMeeting to its provider events, and makes each event
# that is missing. The owner's edit and an unfriend both start it.
#
# It shares the concurrency group and key of GoogleCalendarSyncJob, like
# FriendMeetingPublishJob, so it never runs at the same time as a publish or
# a sync for the same person.
class FriendMeetingUpdateJob < ApplicationJob
  queue_as :high

  limits_concurrency to: 1, group: "GoogleCalendarSyncJob",
                     key: ->(meeting) { "google_calendar_sync_user_#{meeting.user_id}" }

  retry_on MicrosoftGraph::Error, Google::Apis::ServerError, Google::Apis::RateLimitError,
           wait: :polynomially_longer, attempts: 5
  discard_on MicrosoftGraph::AuthError, Google::Apis::AuthorizationError, ActiveJob::DeserializationError

  def perform(meeting)
    FriendMeetingPublisher.new(meeting.user).update(meeting)
  end
end
