# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  color      :string
#  expires_at :datetime
#  name       :string           not null
#  shared     :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_friend_groups_on_expires_at              (expires_at) WHERE (expires_at IS NOT NULL)
#  index_friend_groups_on_user_id_and_lower_name  (user_id, lower((name)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# One friend group that the user owns, with its members, for the
# /api/friends/groups routes. SharedFriendGroupSerializer renders a group
# that someone shared with the user.
#
# Preload memberships: { friendship: [:requester, :addressee] } before a list
# of groups is serialized, or each group runs its own queries.
class FriendGroupSerializer
  # The short form inside each friend of GET /api/friends.
  def self.summary(group)
    { id: group.public_id, name: group.name, color: group.color }
  end

  def initialize(group)
    @group = group
  end

  def as_json(*)
    by_member = @group.memberships_by_member

    self.class.summary(@group).merge(
      shared:               @group.shared,
      members:              by_member.keys.map { |friend| FriendSerializer.new(friend).as_json },
      # The members who opted out of the shared group. The other members do not
      # see them. The owner still does.
      opted_out_member_ids: by_member.select { |_, membership| membership.opted_out? }.keys.map(&:public_id),
      expires_at:           @group.expires_at&.iso8601,
      created_at:           @group.created_at.iso8601,
      updated_at:           @group.updated_at.iso8601
    )
  end
end
