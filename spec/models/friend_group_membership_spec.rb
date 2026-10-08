# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe FriendGroupMembership, type: :model do
  describe "associations and validations" do
    subject { create(:friend_group_membership) }

    it { is_expected.to belong_to(:friend_group) }
    it { is_expected.to belong_to(:friendship) }

    it { is_expected.to validate_uniqueness_of(:friendship_id).scoped_to(:friend_group_id).with_message("is already in this group") }
  end

  # #friendship_belongs_to_group_owner compares two records, the group owner
  # and the friendship, so no single-attribute matcher covers it.
  describe "the friendship check" do
    let(:group) { create(:friend_group) }

    it "accepts an accepted friendship from either side" do
      friendship = create(:friendship, :accepted, requester: create(:user), addressee: group.user)

      expect(build(:friend_group_membership, friend_group: group, friendship: friendship)).to be_valid
    end

    it "refuses a pending request" do
      friendship = create(:friendship, requester: group.user)

      membership = build(:friend_group_membership, friend_group: group, friendship: friendship)

      expect(membership).not_to be_valid
      expect(membership.errors[:friendship]).to include("must be an accepted friendship of the group owner")
    end

    it "refuses a friendship between two other users" do
      friendship = create(:friendship, :accepted)

      expect(build(:friend_group_membership, friend_group: group, friendship: friendship)).not_to be_valid
    end
  end

  it "goes when its group is deleted" do
    membership = create(:friend_group_membership)

    membership.friend_group.destroy!

    expect(described_class.exists?(membership.id)).to be(false)
  end
end
