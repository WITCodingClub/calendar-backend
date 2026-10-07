# frozen_string_literal: true

# One friend in GET /api/friends.
#
# Pass visibility: (the levels of the friendship, or nil). The key is always
# present, so a client can tell "full both ways" (nil) from a missing field.
#
# Pass groups: (the friend's groups for the current user) to add a "groups"
# key. Leave it nil to leave the key out, for example while the friend groups
# flag is off. Load the groups for the whole list first with
# FriendGroup.by_friend_id_for, so the list does not run one query per friend.
class FriendSerializer
  def initialize(friend, visibility: nil, groups: nil)
    @friend = friend
    @visibility = visibility
    @groups = groups
  end

  def as_json(*)
    json = { id: @friend.public_id, name: @friend.full_name, visibility: @visibility }
    json[:groups] = @groups.map { |group| FriendGroupSerializer.summary(group) } unless @groups.nil?
    json
  end
end
