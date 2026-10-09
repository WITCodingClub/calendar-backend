# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  expires_at :datetime
#  name       :string           not null
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
# One friend group, with its members, for the /api/friends/groups routes.
#
# Preload memberships: { friendship: [:requester, :addressee] } before a list
# of groups is serialized, or each group runs its own queries.
class FriendGroupSerializer
  # The short form inside each friend of GET /api/friends.
  def self.summary(group)
    { id: group.public_id, name: group.name }
  end

  def initialize(group)
    @group = group
  end

  def as_json(*)
    self.class.summary(@group).merge(
      members:    @group.members.map { |friend| FriendSerializer.new(friend).as_json },
      expires_at: @group.expires_at&.iso8601,
      created_at: @group.created_at.iso8601,
      updated_at: @group.updated_at.iso8601
    )
  end
end
