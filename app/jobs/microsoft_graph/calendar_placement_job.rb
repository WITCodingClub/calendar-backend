# frozen_string_literal: true

module MicrosoftGraph
  # Moves a person's course events between a calendar of their own and their
  # primary Microsoft calendar, then starts a forced sync that creates the events
  # in the new place.
  #
  # It takes CourseCalendars::UserLock, so a move and a sync for one person
  # never run at the same time.
  class CalendarPlacementJob < ApplicationJob
    include CourseCalendars::UserLock
    include CourseCalendars::ProviderRetries

    queue_as :high

    limits_concurrency_per_user(&:id)

    # A Graph failure stops the move before the row changes, so the job can run
    # again.
    retry_on_provider_errors
    discard_on_auth_errors

    def perform(user, placement)
      return unless MicrosoftGraph.enabled_for?(user)

      service = MicrosoftGraph::CalendarProvider.new(user)
      return unless service.credential

      service.change_placement(placement)
      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
