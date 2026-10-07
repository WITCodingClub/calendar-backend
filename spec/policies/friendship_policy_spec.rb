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
