# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendGroupPolicy do
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

  describe FriendGroupPolicy::Scope do
    it "returns only the user's own groups" do
      other_group = create(:friend_group)

      expect(described_class.new(owner, FriendGroup).resolve).to contain_exactly(group)
      expect(described_class.new(other_group.user, FriendGroup).resolve).to contain_exactly(other_group)
    end

    it "returns nothing without a user" do
      group

      expect(described_class.new(nil, FriendGroup).resolve).to be_empty
    end
  end
end
