# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::Removal do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)   { create(:user) }
  let(:friend) { create(:user) }

  it "removes an accepted friendship in either direction" do
    create(:friendship, :accepted, requester: friend, addressee: user)

    removal = described_class.new(user, friend)
    expect(removal).to be_found
    removal.call

    expect(user.friends).to be_empty
    expect(friend.friends).to be_empty
  end

  it "finds nothing for a pending request, which stays" do
    request = create(:friendship, requester: user, addressee: friend)

    expect(described_class.new(user, friend)).not_to be_found
    expect(request.reload).to be_pending
  end

  it "finds nothing for a stranger, nil, or the user" do
    expect(described_class.new(user, friend)).not_to be_found
    expect(described_class.new(user, nil)).not_to be_found
    expect(described_class.new(user, user)).not_to be_found
  end

  it "finds nothing for an expired friendship" do
    create(:friendship, :accepted, :temporary, requester: user, addressee: friend)

    travel 8.days do
      expect(described_class.new(user, friend)).not_to be_found
    end
  end

  it "removes the friend from the user's groups and keeps the groups" do
    friendship = create(:friendship, :accepted, requester: user, addressee: friend)
    group      = create(:friend_group, user: user)
    create(:friend_group_membership, friend_group: group, friendship: friendship)

    expect { described_class.new(user, friend).call }.to change(FriendGroupMembership, :count).by(-1)
    expect(group.reload.members).to be_empty
  end
end
