# frozen_string_literal: true

# Serializes a friendship from the point of view of one of its two users.
#
#   FriendshipSerializer.new(friendship, viewer).as_json          # the friendship
#   FriendshipSerializer.new(friendship, viewer).as_request       # GET /api/friends/requests
#
# expires_at is an ISO 8601 time, or nil for a permanent friendship.
class FriendshipSerializer
  def self.render_requests(friendships, viewer)
    friendships.map { |f| new(f, viewer).as_request }
  end

  def initialize(friendship, viewer)
    @friendship = friendship
    @viewer     = viewer
  end

  def as_json(*)
    {
      friendship_id: @friendship.public_id,
      status:        @friendship.status,
      expires_at:    expires_at,
      friend:        user_json(friend)
    }
  end

  def as_request
    key = @friendship.requester?(@viewer) ? :to : :from

    {
      request_id: @friendship.public_id,
      key         => user_json(friend),
      created_at: @friendship.created_at.iso8601,
      expires_at: expires_at
    }
  end

  private

  def friend = @friendship.friend_for(@viewer)

  def expires_at = @friendship.expires_at&.iso8601

  def user_json(user)
    { id: user.public_id, name: user.full_name }
  end
end
