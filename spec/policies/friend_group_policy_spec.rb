# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendGroupPolicy do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:group) { create(:friend_group, user: owner) }

  describe "for the owner" do
    subject(:policy) { described_class.new(owner, group) }

    it "allows every action" do
      expect(policy).to have_attributes(index?: true, create?: true, show?: true, update?: true,
                                        destroy?: true, manage_members?: true)
    end
  end

  describe "for another user" do
    subject(:policy) { described_class.new(create(:user), group) }

    it "allows no action on the group" do
      expect(policy).to have_attributes(create?: false, show?: false, update?: false,
                                        destroy?: false, manage_members?: false)
    end
  end

  describe "for an admin" do
    subject(:policy) { described_class.new(create(:user, :owner), group) }

    it "gives no extra access, because groups are private" do
      expect(policy).to have_attributes(show?: false, update?: false, destroy?: false, manage_members?: false)
    end
  end

  describe "without a user" do
    subject(:policy) { described_class.new(nil, group) }

    it "allows nothing" do
      expect(policy).to have_attributes(index?: false, create?: false, show?: false)
    end
  end

  describe "for a member of the group" do
    let(:member) { create(:user) }

    before do
      friendship = create(:friendship, :accepted, requester: owner, addressee: member)
      create(:friend_group_membership, friend_group: group, friendship: friendship)
    end

    it "allows the read-only actions when the group is shared" do
      group.update!(shared: true)

      expect(described_class.new(member, group)).to have_attributes(
        show_shared?: true, update_membership?: true, view_busy_blocks?: true,
        show?: false, update?: false, destroy?: false, manage_members?: false
      )
    end

    it "keeps the group readable but not the busy times after the member opts out" do
      group.update!(shared: true)
      group.membership_for(member).update!(status: :opted_out)

      expect(described_class.new(member, group.reload)).to have_attributes(
        show_shared?: true, update_membership?: true, view_busy_blocks?: false
      )
    end

    it "allows nothing while the group is not shared" do
      expect(described_class.new(member, group)).to have_attributes(show_shared?: false, update_membership?: false,
                                                                   view_busy_blocks?: false)
    end

    it "allows nothing after the group expires" do
      group.update!(shared: true, expires_at: 1.day.from_now)

      travel_to(2.days.from_now) do
        expect(described_class.new(member, group)).to have_attributes(show_shared?: false, view_busy_blocks?: false)
      end
    end
  end

  it "lets the owner read the busy times but not set a member status" do
    expect(described_class.new(owner, group)).to have_attributes(view_busy_blocks?: true, update_membership?: false,
                                                                show_shared?: false)
  end

  describe FriendGroupPolicy::SharedScope do
    it "returns the unexpired shared groups that hold the user" do
      member = create(:user)
      friendship = create(:friendship, :accepted, requester: owner, addressee: member)
      shared = create(:friend_group, :shared, user: owner, expires_at: 1.week.from_now)
      [ group, shared ].each { |g| create(:friend_group_membership, friend_group: g, friendship: friendship) }

      expect(described_class.new(member, FriendGroup).resolve).to contain_exactly(shared)
      expect(described_class.new(owner, FriendGroup).resolve).to be_empty
      expect(described_class.new(nil, FriendGroup).resolve).to be_empty
      travel_to(8.days.from_now) do
        expect(described_class.new(member, FriendGroup).resolve).to be_empty
      end
    end
  end

  describe FriendGroupPolicy::Scope do
    it "returns only the user's own groups" do
      other_group = create(:friend_group)

      expect(described_class.new(owner, FriendGroup).resolve).to contain_exactly(group)
      expect(described_class.new(other_group.user, FriendGroup).resolve).to contain_exactly(other_group)
    end

    it "leaves out an expired group" do
      ending = create(:friend_group, :temporary, user: owner)

      travel_to(8.days.from_now) do
        expect(described_class.new(owner, FriendGroup).resolve).to contain_exactly(group)
      end
      expect(described_class.new(owner, FriendGroup).resolve).to include(ending)
    end

    it "returns nothing without a user" do
      group

      expect(described_class.new(nil, FriendGroup).resolve).to be_empty
    end
  end
end
