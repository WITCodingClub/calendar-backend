# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:other_user) { create(:user, access_level: :user) }
  let(:owner_target) { create(:user, access_level: :owner) }

  permissions :index? do
    it "allows admins to list all users" do
      expect(subject).to permit(admin_user, User)
      expect(subject).to permit(super_admin_user, User)
      expect(subject).to permit(owner_user, User)
    end

    it "denies regular users from listing all users" do
      expect(subject).not_to permit(regular_user, User)
    end
  end

  permissions :show? do
    it "allows users to view their own profile" do
      expect(subject).to permit(regular_user, regular_user)
    end

    it "allows admins to view all profiles for support" do
      expect(subject).to permit(admin_user, other_user)
      expect(subject).to permit(super_admin_user, other_user)
      expect(subject).to permit(owner_user, other_user)
    end

    it "denies users from viewing other users' profiles" do
      expect(subject).not_to permit(regular_user, other_user)
    end
  end

  permissions :create? do
    it "allows admins to create new users" do
      new_user = build(:user)
      expect(subject).to permit(admin_user, new_user)
      expect(subject).to permit(super_admin_user, new_user)
      expect(subject).to permit(owner_user, new_user)
    end

    it "denies regular users from creating users" do
      new_user = build(:user)
      expect(subject).not_to permit(regular_user, new_user)
    end
  end

  permissions :update? do
    it "allows users to update their own profile" do
      expect(subject).to permit(regular_user, regular_user)
    end

    it "allows super_admins to update any profiles" do
      expect(subject).to permit(super_admin_user, other_user)
      expect(subject).to permit(owner_user, other_user)
    end

    it "denies regular admins from updating other users' profiles" do
      expect(subject).not_to permit(admin_user, other_user)
    end

    it "denies regular users from updating other users' profiles" do
      expect(subject).not_to permit(regular_user, other_user)
    end
  end

  permissions :destroy? do
    it "allows users to delete their own account" do
      expect(subject).to permit(regular_user, regular_user)
    end

    it "allows super_admins to delete non-owner accounts" do
      expect(subject).to permit(super_admin_user, other_user)
    end

    it "allows owners to delete any accounts including other owners" do
      expect(subject).to permit(owner_user, owner_target)
    end

    it "denies super_admins from deleting owner accounts" do
      expect(subject).not_to permit(super_admin_user, owner_target)
    end

    it "denies regular admins from deleting any accounts" do
      expect(subject).not_to permit(admin_user, other_user)
    end

    it "denies regular users from deleting other users' accounts" do
      expect(subject).not_to permit(regular_user, other_user)
    end
  end

  describe "Scope" do
    let!(:user1) { create(:user) }
    let!(:user2) { create(:user) }
    let!(:user3) { create(:user) }

    context "as a regular user" do
      it "returns only the user's own record" do
        scope = Pundit.policy_scope(regular_user, User)
        expect(scope).to contain_exactly(regular_user)
      end
    end

    context "as an admin" do
      it "returns all users" do
        scope = Pundit.policy_scope(admin_user, User)
        expect(scope.count).to eq(User.count)
      end
    end
  end
end
