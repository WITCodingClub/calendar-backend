# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecurityEventPolicy, type: :policy do
  subject { described_class }

  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:owner) { create(:user, :owner) }

  let(:user_security_event) { create(:security_event, user: user) }
  let(:other_user_security_event) { create(:security_event, user: create(:user)) }

  permissions :index? do
    it "denies regular users" do
      expect(subject).not_to permit(user, SecurityEvent)
    end

    it "grants admins" do
      expect(subject).to permit(admin, SecurityEvent)
    end

    it "grants super_admins" do
      expect(subject).to permit(super_admin, SecurityEvent)
    end

    it "grants owners" do
      expect(subject).to permit(owner, SecurityEvent)
    end
  end

  permissions :show? do
    it "grants users viewing their own events" do
      expect(subject).to permit(user, user_security_event)
    end

    it "denies users viewing other users' events" do
      expect(subject).not_to permit(user, other_user_security_event)
    end

    it "grants admins viewing any event" do
      expect(subject).to permit(admin, other_user_security_event)
    end

    it "grants super_admins viewing any event" do
      expect(subject).to permit(super_admin, other_user_security_event)
    end

    it "grants owners viewing any event" do
      expect(subject).to permit(owner, other_user_security_event)
    end
  end

  permissions :create? do
    it "denies everyone (system-created only)" do
      expect(subject).not_to permit(user, SecurityEvent)
      expect(subject).not_to permit(admin, SecurityEvent)
      expect(subject).not_to permit(super_admin, SecurityEvent)
      expect(subject).not_to permit(owner, SecurityEvent)
    end
  end

  permissions :update? do
    it "denies everyone (immutable)" do
      expect(subject).not_to permit(user, user_security_event)
      expect(subject).not_to permit(admin, user_security_event)
      expect(subject).not_to permit(super_admin, user_security_event)
      expect(subject).not_to permit(owner, user_security_event)
    end
  end

  permissions :destroy? do
    it "denies regular users" do
      expect(subject).not_to permit(user, user_security_event)
    end

    it "denies admins" do
      expect(subject).not_to permit(admin, user_security_event)
    end

    it "grants super_admins" do
      expect(subject).to permit(super_admin, user_security_event)
    end

    it "grants owners" do
      expect(subject).to permit(owner, user_security_event)
    end

    context "when event belongs to an owner" do
      let(:owner_event) { create(:security_event, user: owner) }

      it "denies super_admins from deleting owner's events" do
        expect(subject).not_to permit(super_admin, owner_event)
      end

      it "grants owners deleting any event" do
        expect(subject).to permit(owner, owner_event)
      end
    end
  end

  describe "Scope" do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }
    let!(:user1_event) { create(:security_event, user: user1) }
    let!(:user2_event) { create(:security_event, user: user2) }
    let!(:no_user_event) { create(:security_event, user: nil) }

    describe ".resolve" do
      it "returns only user's own events for regular users" do
        resolved = SecurityEventPolicy::Scope.new(user1, SecurityEvent).resolve

        expect(resolved).to include(user1_event)
        expect(resolved).not_to include(user2_event)
        expect(resolved).not_to include(no_user_event)
      end

      it "returns all events for admins" do
        resolved = SecurityEventPolicy::Scope.new(admin, SecurityEvent).resolve

        expect(resolved).to include(user1_event)
        expect(resolved).to include(user2_event)
        expect(resolved).to include(no_user_event)
      end

      it "returns all events for super_admins" do
        resolved = SecurityEventPolicy::Scope.new(super_admin, SecurityEvent).resolve

        expect(resolved).to include(user1_event)
        expect(resolved).to include(user2_event)
        expect(resolved).to include(no_user_event)
      end

      it "returns all events for owners" do
        resolved = SecurityEventPolicy::Scope.new(owner, SecurityEvent).resolve

        expect(resolved).to include(user1_event)
        expect(resolved).to include(user2_event)
        expect(resolved).to include(no_user_event)
      end
    end
  end
end
