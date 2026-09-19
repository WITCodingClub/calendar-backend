# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlipperGroups do
  let(:feature) { Flipper[:flipper_groups_spec] }

  # Flipper gives a group block a Flipper::Types::Actor wrapper, so each example
  # goes through Flipper.enabled? to check the real path, not the matcher alone.
  describe "group gates" do
    it "matches every user for the users group" do
      feature.enable_group(:users)

      expect(feature.enabled?(create(:user))).to be(true)
    end

    it "matches an admin, a super admin, and an owner for the admins group" do
      feature.enable_group(:admins)

      expect(feature.enabled?(create(:user, :admin))).to be(true)
      expect(feature.enabled?(create(:user, :super_admin))).to be(true)
      expect(feature.enabled?(create(:user, :owner))).to be(true)
    end

    it "does not match a plain user for the admins group" do
      feature.enable_group(:admins)

      expect(feature.enabled?(create(:user))).to be(false)
    end

    it "matches a super admin and an owner for the super_admins group" do
      feature.enable_group(:super_admins)

      expect(feature.enabled?(create(:user, :super_admin))).to be(true)
      expect(feature.enabled?(create(:user, :owner))).to be(true)
    end

    it "does not match an admin for the super_admins group" do
      feature.enable_group(:super_admins)

      expect(feature.enabled?(create(:user, :admin))).to be(false)
    end

    it "matches only an owner for the owners group" do
      feature.enable_group(:owners)

      expect(feature.enabled?(create(:user, :owner))).to be(true)
      expect(feature.enabled?(create(:user, :super_admin))).to be(false)
    end

    it "does not match a user when no group is enabled" do
      expect(feature.enabled?(create(:user))).to be(false)
    end
  end

  describe ".user_for" do
    it "returns the user that a Flipper actor holds" do
      user = create(:user)

      expect(described_class.user_for(Flipper::Types::Actor.new(user))).to eq(user)
    end

    it "returns a user passed without a wrapper" do
      user = create(:user)

      expect(described_class.user_for(user)).to eq(user)
    end

    it "returns nil for an actor that is not a user" do
      other = Struct.new(:flipper_id).new("Thing;1")

      expect(described_class.user_for(Flipper::Types::Actor.new(other))).to be_nil
    end
  end

  describe ".match?" do
    it "returns false for an actor that is not a user" do
      other = Struct.new(:flipper_id).new("Thing;1")

      expect(described_class.match?(:users, Flipper::Types::Actor.new(other))).to be(false)
    end
  end
end
