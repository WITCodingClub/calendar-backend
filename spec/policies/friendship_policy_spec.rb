# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendshipPolicy do
  include ActiveSupport::Testing::TimeHelpers

  let(:requester) { create(:user) }
  let(:addressee) { create(:user) }
  let(:stranger)  { create(:user) }

  describe "#view_schedule?" do
    let(:friendship) { create(:friendship, :accepted, :temporary, requester: requester, addressee: addressee) }

    it "permits both sides before the expiry date" do
      expect(described_class.new(requester, friendship).view_schedule?).to be(true)
      expect(described_class.new(addressee, friendship).view_schedule?).to be(true)
    end

    it "refuses both sides after the expiry date" do
      friendship

      travel 8.days do
        expect(described_class.new(requester, friendship).view_schedule?).to be(false)
        expect(described_class.new(addressee, friendship).view_schedule?).to be(false)
      end
    end

    it "refuses a stranger" do
      expect(described_class.new(stranger, friendship).view_schedule?).to be(false)
    end
  end

  describe "#update_expiry?" do
    let(:friendship) { create(:friendship, :temporary, requester: requester, addressee: addressee) }

    it "permits both sides of an unexpired friendship or request" do
      expect(described_class.new(requester, friendship).update_expiry?).to be(true)
      expect(described_class.new(addressee, friendship).update_expiry?).to be(true)
    end

    it "refuses a stranger" do
      expect(described_class.new(stranger, friendship).update_expiry?).to be(false)
    end

    it "refuses after the expiry date, so an ended friendship cannot come back" do
      friendship

      travel 8.days do
        expect(described_class.new(requester, friendship).update_expiry?).to be(false)
      end
    end
  end

  describe "end date consent" do
    # A sent a one-week request. B (the addressee) accepted it.
    let(:friendship) { create(:friendship, :accepted, :temporary, requester: requester, addressee: addressee) }

    def policy(user) = described_class.new(user, friendship.reload)

    it "does not let B make A's one-week friendship permanent alone" do
      expect(friendship.change_expiry!(to: nil, by: addressee)).to eq(:proposed)

      expect(friendship.reload.expires_at).to be_present
      expect(policy(addressee).accept_expiry?).to be(false)
      expect(policy(requester).accept_expiry?).to be(true)
    end

    it "does not let A extend the date alone either" do
      friendship.change_expiry!(to: 30.days.from_now, by: requester)

      expect(friendship.reload.expires_at).to be < 8.days.from_now
      expect(policy(requester).accept_expiry?).to be(false)
      expect(policy(addressee).accept_expiry?).to be(true)
    end

    it "lets either side shorten the date alone" do
      expect(policy(requester).update_expiry?).to be(true)
      expect(policy(addressee).update_expiry?).to be(true)
      expect(friendship.change_expiry!(to: 2.days.from_now, by: addressee)).to eq(:shortened)
    end

    it "lets either side end the friendship alone" do
      expect(policy(requester).destroy?).to be(true)
      expect(policy(addressee).destroy?).to be(true)
    end

    describe "#accept_expiry?" do
      it "refuses when there is no proposal" do
        expect(policy(requester).accept_expiry?).to be(false)
        expect(policy(addressee).accept_expiry?).to be(false)
      end

      it "refuses a stranger" do
        friendship.change_expiry!(to: nil, by: requester)

        expect(policy(stranger).accept_expiry?).to be(false)
      end

      it "refuses after the friendship expires, because the proposal ends with it" do
        friendship.change_expiry!(to: nil, by: requester)

        travel 8.days do
          expect(policy(addressee).accept_expiry?).to be(false)
          expect(policy(addressee).decline_expiry?).to be(false)
        end
      end

      it "refuses after someone shortens the date, because that clears the proposal" do
        friendship.change_expiry!(to: nil, by: requester)
        friendship.change_expiry!(to: 2.days.from_now, by: requester)

        expect(policy(addressee).accept_expiry?).to be(false)
      end
    end

    describe "#decline_expiry?" do
      it "lets the other side decline and the proposer withdraw" do
        friendship.change_expiry!(to: nil, by: requester)

        expect(policy(addressee).decline_expiry?).to be(true)
        expect(policy(requester).decline_expiry?).to be(true)
      end

      it "refuses when there is no proposal, and refuses a stranger" do
        expect(policy(addressee).decline_expiry?).to be(false)

        friendship.change_expiry!(to: nil, by: requester)
        expect(policy(stranger).decline_expiry?).to be(false)
      end
    end

    context "with a pending request" do
      let(:friendship) { create(:friendship, :temporary, requester: requester, addressee: addressee) }

      it "lets the addressee accept the request with the requester's date as is" do
        expect(policy(addressee).accept?).to be(true)
      end

      it "applies an earlier date from the addressee at once" do
        expect(friendship.change_expiry!(to: 2.days.from_now, by: addressee)).to eq(:shortened)
      end

      it "makes a later date from the addressee a counter-proposal that only the requester can accept" do
        expect(friendship.change_expiry!(to: nil, by: addressee)).to eq(:proposed)

        expect(policy(addressee).accept_expiry?).to be(false)
        expect(policy(requester).accept_expiry?).to be(true)
      end

      it "makes a later date from the requester a proposal too" do
        expect(friendship.change_expiry!(to: 30.days.from_now, by: requester)).to eq(:proposed)

        expect(policy(requester).accept_expiry?).to be(false)
        expect(policy(addressee).accept_expiry?).to be(true)
      end
    end
  end

  describe "#accept?" do
    it "refuses an expired request" do
      friendship = create(:friendship, :temporary, requester: requester, addressee: addressee)

      expect(described_class.new(addressee, friendship).accept?).to be(true)
      travel 8.days do
        expect(described_class.new(addressee, friendship).accept?).to be(false)
      end
    end
  end

  describe "Scope" do
    it "leaves out an expired friendship" do
      kept    = create(:friendship, :accepted, requester: requester)
      expired = create(:friendship, :accepted, :temporary, requester: requester)

      travel 8.days do
        resolved = described_class::Scope.new(requester, Friendship).resolve

        expect(resolved).to include(kept)
        expect(resolved).not_to include(expired)
      end
    end
  end
end
