# frozen_string_literal: true

# Moves a person's course events between a calendar of their own and their
# primary Microsoft calendar, then starts a forced sync that creates the events
# in the new place.
#
# It shares the concurrency group and key of GoogleCalendarSyncJob, so a move
# and a sync for one person never run at the same time. Solid Queue puts the
# group in front of the key, and the group is the job class unless it is set.
class MicrosoftGraphCalendarPlacementJob < ApplicationJob
  queue_as :high

  limits_concurrency to: 1, group: "GoogleCalendarSyncJob",
                     key: ->(user, _placement) { "google_calendar_sync_user_#{user.id}" }

  # A Graph failure stops the move before the row changes, so the job can run
  # again. An auth failure needs a new sign-in, so that job is dropped.
  retry_on MicrosoftGraph::Error, wait: :polynomially_longer, attempts: 5
  discard_on MicrosoftGraph::AuthError

  def perform(user, placement)
    return unless MicrosoftGraph.enabled_for?(user)

    service = MicrosoftGraphCalendarService.new(user)
    return unless service.credential

    service.change_placement(placement)
    GoogleCalendarSyncJob.perform_later(user, force: true)
  end
end
