# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
# Database name: primary
#
#  id           :bigint           not null, primary key
#  status       :integer          default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  addressee_id :bigint           not null
#  requester_id :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id                   (addressee_id)
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id                   (requester_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
require "rails_helper"

RSpec.describe Friendship do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:requester).class_name("User") }
    it { is_expected.to belong_to(:addressee).class_name("User") }
  end

  describe "validations" do
    subject { build(:friendship, requester: user1, addressee: user2) }

    it "prevents duplicate friendships" do
      create(:friendship, requester: user1, addressee: user2)
      duplicate = build(:friendship, requester: user1, addressee: user2)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:requester_id]).to include("friendship already exists")
    end

    it "prevents self-friending" do
      friendship = build(:friendship, requester: user1, addressee: user1)
      expect(friendship).not_to be_valid
      expect(friendship.errors[:addressee]).to include("cannot be yourself")
    end

    it "prevents reverse duplicates" do
      create(:friendship, requester: user1, addressee: user2)
      reverse = build(:friendship, requester: user2, addressee: user1)
      expect(reverse).not_to be_valid
      expect(reverse.errors[:base]).to include("A friendship request already exists between these users")
    end
  end

  describe "scopes" do
    let!(:pending_request) { create(:friendship, requester: user1, addressee: user2) }
    let(:user3) { create(:user) }
    let!(:accepted_friendship) { create(:friendship, :accepted, requester: user1, addressee: user3) }

    describe ".involving" do
      it "returns friendships where user is requester or addressee" do
        expect(described_class.involving(user1)).to include(pending_request, accepted_friendship)
      end
    end

    describe ".pending_for" do
      it "returns pending requests where user is addressee" do
        expect(described_class.pending_for(user2)).to include(pending_request)
        expect(described_class.pending_for(user1)).not_to include(pending_request)
      end
    end

    describe ".outgoing_from" do
      it "returns pending requests where user is requester" do
        expect(described_class.outgoing_from(user1)).to include(pending_request)
        expect(described_class.outgoing_from(user2)).not_to include(pending_request)
      end
    end

    describe ".accepted_for" do
      it "returns accepted friendships for user" do
        expect(described_class.accepted_for(user1)).to include(accepted_friendship)
        expect(described_class.accepted_for(user1)).not_to include(pending_request)
      end
    end
  end

  describe "#friend_for" do
    let(:friendship) { create(:friendship, requester: user1, addressee: user2) }

    it "returns the other user" do
      expect(friendship.friend_for(user1)).to eq(user2)
      expect(friendship.friend_for(user2)).to eq(user1)
    end
  end

  describe "#requester?" do
    let(:friendship) { create(:friendship, requester: user1, addressee: user2) }

    it "returns true for the requester" do
      expect(friendship.requester?(user1)).to be true
      expect(friendship.requester?(user2)).to be false
    end
  end

  describe "#addressee?" do
    let(:friendship) { create(:friendship, requester: user1, addressee: user2) }

    it "returns true for the addressee" do
      expect(friendship.addressee?(user2)).to be true
      expect(friendship.addressee?(user1)).to be false
    end
  end

  describe "public_id" do
    it "has frn_ prefix" do
      friendship = create(:friendship, requester: user1, addressee: user2)
      expect(friendship.public_id).to start_with("frn_")
    end
  end

  describe "enum status" do
    it "defaults to pending" do
      friendship = create(:friendship, requester: user1, addressee: user2)
      expect(friendship).to be_pending
    end

    it "can be accepted" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(friendship).to be_accepted
    end
  end
end
