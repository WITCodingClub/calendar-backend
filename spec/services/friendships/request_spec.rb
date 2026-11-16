# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::Request do
  let(:requester) { create(:user) }
  let(:addressee) { create(:user) }

  def enable(flag, user)
    Flipper.enable_actor(flag, user)
  end

  def reason_of
    yield
    nil
  rescue Friendships::OptionError => e
    e.reason
  end

  describe ".build" do
    it "builds a pending request with the default level" do
      friendship = described_class.build(requester, addressee)

      expect(friendship).to be_new_record
      expect(friendship).to have_attributes(requester: requester, addressee: addressee, requester_visibility: "full")
    end

    it "refuses a request to yourself" do
      expect(reason_of { described_class.build(requester, requester) }).to eq(:self)
    end

    it "refuses a sharing level while the availability-only flag is off" do
      expect(reason_of { described_class.build(requester, addressee, visibility: "availability_only") })
        .to eq(:visibility_disabled)
    end

    it "takes a valid sharing level while the flag is on" do
      enable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, requester)

      friendship = described_class.build(requester, addressee, visibility: "availability_only")

      expect(friendship.requester_visibility).to eq("availability_only")
    end

    it "refuses an unknown sharing level" do
      enable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, requester)

      expect(reason_of { described_class.build(requester, addressee, visibility: "secret") }).to eq(:invalid_visibility)
    end

    it "refuses an end date while the friend_expiry flag is off" do
      expect(reason_of { described_class.build(requester, addressee, expires_at: 1.week.from_now.to_date.iso8601) })
        .to eq(:expiry_disabled)
    end

    context "with the friend_expiry flag on" do
      before { enable(FeatureFlags::FRIEND_EXPIRY, requester) }

      it "sets the end date" do
        friendship = described_class.build(requester, addressee, expires_at: "2099-12-01")

        expect(friendship.expires_at).to eq(Friendships::ExpiryTime.parse("2099-12-01"))
      end

      it "refuses an end date it cannot read" do
        expect(reason_of { described_class.build(requester, addressee, expires_at: "soon") }).to eq(:invalid_expiry)
      end

      it "refuses an end date in the past" do
        expect(reason_of { described_class.build(requester, addressee, expires_at: "2000-01-01") }).to eq(:past_expiry)
      end
    end
  end

  describe ".accept!" do
    let(:friendship) { create(:friendship, requester: requester, addressee: addressee) }

    it "accepts the request" do
      described_class.accept!(friendship)

      expect(friendship.reload).to be_accepted
    end

    it "sets the addressee's level with the addressee's flag" do
      enable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, addressee)

      described_class.accept!(friendship, visibility: "availability_only")

      expect(friendship.reload.addressee_visibility).to eq("availability_only")
    end
  end
end
