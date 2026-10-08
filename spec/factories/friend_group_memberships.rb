# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_group_memberships
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  friend_group_id :bigint           not null
#  friendship_id   :bigint           not null
#
# Indexes
#
#  index_friend_group_memberships_on_friendship_id         (friendship_id)
#  index_friend_group_memberships_on_group_and_friendship  (friend_group_id,friendship_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (friend_group_id => friend_groups.id) ON DELETE => cascade
#  fk_rails_...  (friendship_id => friendships.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :friend_group_membership do
    # The membership checks that the friendship involves the group owner by id,
    # so the group and its owner need a real persisted id even when this
    # factory is built (not created).
    association :friend_group, strategy: :create
    friendship { association :friendship, :accepted, requester: friend_group.user, strategy: :create }
  end
end
