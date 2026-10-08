# frozen_string_literal: true

# Runs FriendMeetingPublisher#resume after a person connects a calendar
# account again: it finishes the meetings they deleted while the token was
# refused, and puts back the events that a disconnect removed.
#
# It shares the concurrency group and key of GoogleCalendarSyncJob, so it
# never runs at the same time as a sync or another meeting job for the
# person.
class FriendMeetingResumeJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, group: "GoogleCalendarSyncJob",
                     key: ->(user) { "google_calendar_sync_user_#{user.id}" }

  discard_on ActiveJob::DeserializationError

  def perform(user)
    FriendMeetingPublisher.new(user).resume
  end
end
