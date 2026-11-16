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

    def perform
      removed = MODELS.to_h { |model| [ model.name, model.purge_expired ] }

      Rails.logger.info "[Cleanup::ExpiredRecordsJob] Removed #{removed}"

      removed
    end
  end
end
