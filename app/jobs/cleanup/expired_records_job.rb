# frozen_string_literal: true

module Cleanup
  # Deletes the expired rows of every Expirable model that has nothing to keep
  # after expiry. An expired row already grants nothing: each model hides it
  # (scope unexpired, expired?). This job only removes the rows, so the same
  # two people can send a new friend request, and the token tables do not grow
  # without bound. Meeting links (OldMeetingLinksJob) and sessions stay longer,
  # because their owners still see them in a list.
  class ExpiredRecordsJob < ApplicationJob
    queue_as :low

    MODELS = [ Friendship, FriendGroup, PasskeyHandoff, WebauthnChallenge ].freeze

    # Each model is purged on its own: a failure in one is reported, and the
    # others still go. The next run tries the failed one again.
    def perform
      removed = MODELS.to_h { |model| [ model.name, purge(model) ] }

      Rails.logger.info "[Cleanup::ExpiredRecordsJob] Removed #{removed}"

      removed
    end

    private

    def purge(model)
      model.purge_expired
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { model: model.name })
      nil
    end
  end
end
