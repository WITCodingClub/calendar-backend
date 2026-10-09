# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendGroups::RemoveExpiredJob do
  include ActiveSupport::Testing::TimeHelpers

  it "deletes expired groups and keeps the rest" do
    permanent = create(:friend_group)
    later     = create(:friend_group, expires_at: 30.days.from_now)
    ending    = create(:friend_group, :temporary)

    travel 8.days do
      expect(described_class.perform_now).to eq(removed: 1)
    end

    expect(FriendGroup.all).to contain_exactly(permanent, later)
    expect(FriendGroup.exists?(ending.id)).to be(false)
  end

  it "removes the memberships and keeps the friendships" do
    group      = create(:friend_group, :temporary, :with_members)
    friendship = group.friendships.first

    travel 8.days do
      described_class.perform_now
    end

    expect(FriendGroupMembership.where(friend_group_id: group.id)).to be_empty
    expect(Friendship.exists?(friendship.id)).to be(true)
  end
end
