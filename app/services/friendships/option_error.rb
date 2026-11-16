# frozen_string_literal: true

module Friendships
  # A friend request, an accept or an end date with a value that the user
  # cannot send. Each surface turns +reason+ into its own answer:
  #
  # - :self                 the user sent a request to themselves
  # - :visibility_disabled  a sharing level while the availability-only flag is off
  # - :invalid_visibility   a sharing level that Friendship::VISIBILITIES does not have
  # - :expiry_disabled      an end date while the friend_expiry flag is off
  # - :invalid_expiry       an end date that Friendships::ExpiryTime cannot read
  # - :past_expiry          an end date that is not in the future
  class OptionError < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end
end
