# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendGroup, type: :model do
  describe "associations and validations" do
    subject { create(:friend_group) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:memberships).class_name("FriendGroupMembership").dependent(:destroy) }
    it { is_expected.to have_many(:friendships).through(:memberships) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(FriendGroup::NAME_MAX_LENGTH) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id).case_insensitive }
  end

  it "squishes the name" do
    expect(build(:friend_group, name: "  Study   group ").name).to eq("Study group")
  end

  it "lets two users use the same name" do
    create(:friend_group, name: "Roommates")

    expect(build(:friend_group, name: "Roommates")).to be_valid
  end

  it "has a public id with the fgr prefix" do
    expect(create(:friend_group).public_id).to start_with("fgr_")
  end

  describe ".enabled_for?" do
    let(:user) { create(:user) }

    after { Flipper.disable(FlipperFlags::FRIEND_GROUPS) }

    it "is off by default" do
      expect(described_class.enabled_for?(user)).to be(false)
    end

    it "is on for a user the flag names" do
      Flipper.enable_actor(FlipperFlags::FRIEND_GROUPS, user)

      expect(described_class.enabled_for?(user)).to be(true)
      expect(described_class.enabled_for?(create(:user))).to be(false)
    end

    it "is off without a user" do
      Flipper.enable(FlipperFlags::FRIEND_GROUPS)

      expect(described_class.enabled_for?(nil)).to be(false)
    end
  end

  describe ".by_friend_id_for" do
    let(:owner) { create(:user) }

    it "maps each friend to the owner's groups, sorted by name" do
      friendship = create(:friendship, :accepted, requester: create(:user), addressee: owner)
      roommates  = create(:friend_group, user: owner, name: "Roommates")
      study      = create(:friend_group, user: owner, name: "Lab partners")
      create(:friend_group_membership, friend_group: roommates, friendship: friendship)
      create(:friend_group_membership, friend_group: study, friendship: friendship)

      result = described_class.by_friend_id_for(owner)

      expect(result[friendship.requester_id]).to eq([ study, roommates ])
    end

    it "leaves out the groups of other users" do
      create(:friend_group, :with_members)

      expect(described_class.by_friend_id_for(owner)).to be_empty
    end

    it "answers an empty list for a friend in no group" do
      expect(described_class.by_friend_id_for(owner)[create(:user).id]).to eq([])
    end
  end

  describe "#members" do
    it "returns the friend users, sorted by name" do
      group = create(:friend_group)
      zed   = create(:user, first_name: "Zed", last_name: "Lane")
      amy   = create(:user, first_name: "Amy", last_name: "Lane")
      [ zed, amy ].each do |friend|
        friendship = create(:friendship, :accepted, requester: friend, addressee: group.user)
        create(:friend_group_membership, friend_group: group, friendship: friendship)
      end

      expect(group.reload.members).to eq([ amy, zed ])
    end
  end
end
