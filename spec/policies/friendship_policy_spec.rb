# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendshipPolicy, type: :policy do
  subject { described_class }

  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:user3) { create(:user) }

  permissions :create? do
    it "allows requester to create" do
      friendship = build(:friendship, requester: user1, addressee: user2)
      expect(subject).to permit(user1, friendship)
    end

    it "denies non-requester" do
      friendship = build(:friendship, requester: user1, addressee: user2)
      expect(subject).not_to permit(user3, friendship)
    end
  end

  permissions :accept? do
    it "allows addressee to accept pending request" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).to permit(user2, friendship)
    end

    it "denies requester from accepting" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).not_to permit(user1, friendship)
    end

    it "denies accepting already-accepted friendship" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(subject).not_to permit(user2, friendship)
    end
  end

  permissions :decline? do
    it "allows addressee to decline pending request" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).to permit(user2, friendship)
    end

    it "denies requester from declining" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).not_to permit(user1, friendship)
    end
  end

  permissions :cancel? do
    it "allows requester to cancel pending request" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).to permit(user1, friendship)
    end

    it "denies addressee from canceling" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).not_to permit(user2, friendship)
    end
  end

  permissions :destroy? do
    it "allows either party to unfriend" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(subject).to permit(user1, friendship)
      expect(subject).to permit(user2, friendship)
    end

    it "denies unrelated users" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(subject).not_to permit(user3, friendship)
    end
  end

  permissions :view_schedule? do
    it "allows either party of accepted friendship" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(subject).to permit(user1, friendship)
      expect(subject).to permit(user2, friendship)
    end

    it "denies for pending friendships" do
      friendship = create(:friendship, :pending, requester: user1, addressee: user2)
      expect(subject).not_to permit(user1, friendship)
      expect(subject).not_to permit(user2, friendship)
    end

    it "denies unrelated users" do
      friendship = create(:friendship, :accepted, requester: user1, addressee: user2)
      expect(subject).not_to permit(user3, friendship)
    end
  end

  describe "Scope" do
    let!(:friendship1) { create(:friendship, requester: user1, addressee: user2) }
    let!(:friendship2) { create(:friendship, requester: user2, addressee: user3) }
    let!(:friendship3) { create(:friendship, requester: user3, addressee: create(:user)) }

    it "returns only friendships involving the user" do
      scope = Pundit.policy_scope(user1, Friendship)
      expect(scope).to contain_exactly(friendship1)
    end

    it "includes friendships where user is requester or addressee" do
      scope = Pundit.policy_scope(user2, Friendship)
      expect(scope).to contain_exactly(friendship1, friendship2)
    end
  end
end
