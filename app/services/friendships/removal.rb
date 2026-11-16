# frozen_string_literal: true

module Friendships
  # Ends a friendship, for the API, the dashboard and the admin user page. Each
  # surface finds the friendship here, authorizes it in its own way, and then
  # calls #call. Only an accepted friendship that has not expired can be
  # removed: a pending request is declined or withdrawn instead.
  class Removal
    attr_reader :friendship

    # +friend+ can be nil (an unknown id). Then #friendship is nil.
    def initialize(user, friend)
      @friendship = Friendship.accepted_between(user, friend) if friend
    end

    def found? = friendship.present?

    # The friend group memberships go with the friendship, and the two users
    # come off each other's future meetings (Friendship callbacks).
    def call
      friendship.destroy!
    end
  end
end
