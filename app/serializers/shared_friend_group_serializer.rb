# frozen_string_literal: true

# One friend group that someone shared with the viewer, for the
# /api/friends/shared_groups routes. The viewer sees the owner and every member
# who did not opt out, also members who are not the viewer's friends. It has
# no "shared" key: every group here is shared. "status" is the viewer's own
# status in the group.
#
# Preload :user and memberships: { friendship: [:requester, :addressee] }
# before a list of groups is serialized, or each group runs its own queries.
class SharedFriendGroupSerializer
  def initialize(group, viewer:)
    @group  = group
    @viewer = viewer
  end

  def as_json(*)
    {
      id:         @group.public_id,
      name:       @group.name,
      color:      @group.color,
      status:     @group.membership_for(@viewer)&.status,
      owner:      FriendSerializer.new(@group.user).as_json,
      members:    @group.shared_people.drop(1).map { |member| FriendSerializer.new(member).as_json },
      expires_at: @group.expires_at&.iso8601,
      created_at: @group.created_at.iso8601,
      updated_at: @group.updated_at.iso8601
    }
  end
end
