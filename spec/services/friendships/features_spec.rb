# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::Features do
  let(:viewer) { create(:user) }
  let(:friendship) { create(:friendship, :accepted, requester: viewer) }

  it "reads each friends flag for the user" do
    Flipper.enable_actor(FeatureFlags::FRIEND_EXPIRY, viewer)

    expect(described_class.expiry?(viewer)).to be(true)
    expect(described_class.availability_only?(viewer)).to be(false)
    expect(described_class.groups?(viewer)).to be(false)
    expect(described_class.groups?(nil)).to be(false)
  end

  describe ".busy_times_readable?" do
    it "is false for a friend who shares the full schedule while the flag is off" do
      expect(described_class.busy_times_readable?(friendship, viewer)).to be(false)
    end

    it "is true for a friend who shares only availability" do
      friendship.update!(addressee_visibility: "availability_only")

      expect(described_class.busy_times_readable?(friendship, viewer)).to be(true)
    end

    it "is true while the flag is on" do
      Flipper.enable_actor(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, viewer)

      expect(described_class.busy_times_readable?(friendship, viewer)).to be(true)
    end
  end
end
