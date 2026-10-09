# frozen_string_literal: true

module FriendMeetings
  # Puts a new FriendMeeting in the person's provider calendars.
  #
  # It shares the concurrency group and key of CourseCalendars::SyncJob, like
  # MicrosoftGraph::CalendarPlacementJob, so a publish and a sync for one person
  # never run at the same time. A retry skips each calendar that already has the
  # meeting.
  class PublishJob < ApplicationJob
    queue_as :high

    limits_concurrency to: 1, group: CourseCalendars::SyncJob::CONCURRENCY_GROUP,
                       key: ->(meeting) { "google_calendar_sync_user_#{meeting.user_id}" }

    retry_on MicrosoftGraph::Error, Google::Apis::ServerError, Google::Apis::RateLimitError,
             wait: :polynomially_longer, attempts: 5
    discard_on MicrosoftGraph::AuthError, Google::Apis::AuthorizationError, ActiveJob::DeserializationError

    def perform(meeting)
      FriendMeetings::Publisher.new(meeting.user).publish(meeting)
    end
  end
end
