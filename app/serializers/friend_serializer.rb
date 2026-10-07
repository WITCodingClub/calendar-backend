# frozen_string_literal: true

# One friend in GET /api/friends.
#
# Pass visibility: (the levels of the friendship, or nil) to add a "visibility"
# key. GET /api/friends always passes it, so the key is there even when nil.
# Group members leave it out.
#
# Pass groups: (the friend's groups for the current user) to add a "groups"
# key. Leave it nil to leave the key out, for example while the friend groups
# flag is off. Load the groups for the whole list first with
# FriendGroup.by_friend_id_for, so the list does not run one query per friend.
#
# Pass expires_at: (the friendship's end time, or nil when it is permanent) to
# add an "expires_at" key as an ISO 8601 time. Group members leave it out.
class FriendSerializer
  OMIT = Object.new.freeze
  private_constant :OMIT

  def initialize(friend, visibility: OMIT, groups: nil, expires_at: OMIT)
    @friend = friend
    @visibility = visibility
    @groups = groups
    @expires_at = expires_at
  end

  def as_json(*)
    json = { id: @friend.public_id, name: @friend.full_name }
    json[:visibility] = @visibility unless @visibility.equal?(OMIT)
    json[:groups] = @groups.map { |group| FriendGroupSerializer.summary(group) } unless @groups.nil?
    json[:expires_at] = @expires_at&.iso8601 unless @expires_at.equal?(OMIT)
    json
  end
end
