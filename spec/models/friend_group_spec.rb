# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_friend_groups_on_user_id_and_lower_name  (user_id, lower((name)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
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

    after { Flipper.disable(FeatureFlags::FRIEND_GROUPS) }

    it "is off by default" do
      expect(described_class.enabled_for?(user)).to be(false)
    end

    it "is on for a user the flag names" do
      Flipper.enable_actor(FeatureFlags::FRIEND_GROUPS, user)

      expect(described_class.enabled_for?(user)).to be(true)
      expect(described_class.enabled_for?(create(:user))).to be(false)
    end

    it "is off without a user" do
      Flipper.enable(FeatureFlags::FRIEND_GROUPS)

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

  describe "#save_with_members!" do
    let(:group)  { create(:friend_group) }
    let(:owner)  { group.user }
    let(:friend) { create(:user).tap { |u| create(:friendship, :accepted, requester: u, addressee: owner) } }

    it "replaces the members" do
      old = create(:user).tap { |u| create(:friendship, :accepted, requester: u, addressee: owner) }
      create(:friend_group_membership, friend_group: group, friendship: owner.accepted_friendship_with(old))

      group.save_with_members!({}, friend_ids: [ friend.public_id ])

      expect(group.reload.members).to eq([ friend ])
    end

    it "leaves the members alone when friend_ids is nil" do
      create(:friend_group_membership, friend_group: group, friendship: owner.accepted_friendship_with(friend))

      group.save_with_members!({ name: "Renamed" })

      expect(group.reload.members).to eq([ friend ])
    end

    it "raises with the bad ids and changes nothing" do
      stranger = create(:user)

      expect { group.save_with_members!({ name: "Renamed" }, friend_ids: [ friend.public_id, stranger.public_id ]) }
        .to raise_error(described_class::UnknownFriends) { |error| expect(error.ids).to eq([ stranger.public_id ]) }
      expect(group.reload.name).not_to eq("Renamed")
      expect(group.memberships).to be_empty
    end
  end

  # Every check of "is this an accepted friendship" goes through
  # User#accepted_friendships. When it answers none, all of them must agree.
  describe "the one accepted-friendship rule" do
    let(:group)  { create(:friend_group) }
    let(:owner)  { group.user }
    let(:friend) { create(:user).tap { |u| create(:friendship, :accepted, requester: u, addressee: owner) } }
    let!(:membership) do
      create(:friend_group_membership, friend_group: group, friendship: owner.accepted_friendship_with(friend))
    end

    before { allow_any_instance_of(User).to receive(:accepted_friendships).and_return(Friendship.none) } # rubocop:disable RSpec/AnyInstance

    it "is followed by User#accepted_friendship_with" do
      expect(owner.accepted_friendship_with(friend)).to be_nil
    end

    it "is followed by the membership validation" do
      expect(membership.reload).not_to be_valid
    end

    it "is followed by #members" do
      expect(described_class.find(group.id).members).to be_empty
    end

    it "is followed by .by_friend_id_for" do
      expect(described_class.by_friend_id_for(owner)[friend.id]).to eq([])
    end

    it "is followed by member replacement" do
      expect { group.save_with_members!({}, friend_ids: [ friend.public_id ]) }
        .to raise_error(described_class::UnknownFriends)
    end
  end
end
