# frozen_string_literal: true

# Deletes the provider events of a FriendMeeting that its owner cancelled,
# then the meeting. Until it is done, the meeting stays cancelled, so no sync
# puts it back.
#
# It shares the concurrency group and key of GoogleCalendarSyncJob, like
# FriendMeetingPublishJob, so it never runs at the same time as a publish or
# a sync for the same person.
class FriendMeetingRemoveJob < ApplicationJob
  queue_as :high

  limits_concurrency to: 1, group: "GoogleCalendarSyncJob",
                     key: ->(meeting) { "google_calendar_sync_user_#{meeting.user_id}" }

  retry_on MicrosoftGraph::Error, Google::Apis::ServerError, Google::Apis::RateLimitError,
           wait: :polynomially_longer, attempts: 5
  discard_on MicrosoftGraph::AuthError, Google::Apis::AuthorizationError, ActiveJob::DeserializationError

  def perform(meeting)
    FriendMeetingPublisher.new(meeting.user).remove(meeting)
  end
end
