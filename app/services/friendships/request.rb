# frozen_string_literal: true

module Friendships
  # A friend request and its accept, for the API and the dashboard. Each one
  # reads the optional sharing level and end date with the same flags and
  # rules, and raises Friendships::OptionError for a value the user cannot send.
  # The caller authorizes with FriendshipPolicy.
  module Request
    module_function

    # The new request, not saved yet.
    def build(requester, addressee, visibility: nil, expires_at: nil)
      raise OptionError, :self if requester.id == addressee.id

      friendship = Friendship.new(requester: requester, addressee: addressee)
      level = visibility_for(requester, visibility)
      friendship.requester_visibility = level if level
      friendship.expires_at = expiry_for(requester, expires_at) if expires_at.present?
      friendship
    end

    def accept!(friendship, visibility: nil)
      level = visibility_for(friendship.addressee, visibility)
      friendship.addressee_visibility = level if level
      friendship.accepted!
    end

    # The sharing level, or nil when the value is blank.
    def visibility_for(user, value)
      return nil if value.blank?
      raise OptionError, :visibility_disabled unless Features.availability_only?(user)
      raise OptionError, :invalid_visibility unless Friendship.valid_visibility?(value)

      value.to_s
    end

    def expiry_for(user, value)
      raise OptionError, :expiry_disabled unless Features.expiry?(user)

      expires_at = ExpiryTime.parse(value)
      raise OptionError, :invalid_expiry if expires_at.nil?
      raise OptionError, :past_expiry unless expires_at.future?

      expires_at
    end
  end
end
