# frozen_string_literal: true

# Renders the two visibility levels of one friendship, as seen by +viewer+.
# "mine" is the level the viewer set for their own schedule. "theirs" is the
# level the friend set, which decides what the viewer can read.
class FriendshipVisibilitySerializer
  def initialize(friendship, viewer:)
    @friendship = friendship
    @viewer     = viewer
  end

  def as_json(*)
    friend = @friendship.friend_for(@viewer)

    {
      friend_id: friend.public_id,
      mine:      @friendship.visibility_set_by(@viewer),
      theirs:    @friendship.visibility_set_by(friend)
    }
  end
end
