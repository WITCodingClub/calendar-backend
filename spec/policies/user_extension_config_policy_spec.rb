# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserExtensionConfigPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:other_user) { create(:user, access_level: :user) }
  let(:owner_target) { create(:user, access_level: :owner) }

  let(:owned_config) { create(:user_extension_config, user: regular_user) }
  let(:other_config) { create(:user_extension_config, user: other_user) }
  let(:owner_config) { create(:user_extension_config, user: owner_target) }

  permissions :index? do
    it "allows admins to list all configs" do
      expect(subject).to permit(admin_user, owned_config)
      expect(subject).to permit(super_admin_user, owned_config)
      expect(subject).to permit(owner_user, owned_config)
    end

    it "denies regular users from listing all configs" do
      expect(subject).not_to permit(regular_user, owned_config)
    end
  end

  permissions :show? do
    it "allows users to view their own config" do
      expect(subject).to permit(regular_user, owned_config)
    end

    it "allows admins to view any config for support" do
      expect(subject).to permit(admin_user, other_config)
      expect(subject).to permit(super_admin_user, other_config)
      expect(subject).to permit(owner_user, other_config)
    end

    it "denies regular users from viewing other users' configs" do
      expect(subject).not_to permit(regular_user, other_config)
    end
  end

  permissions :create? do
    it "allows users to create their own config" do
      new_config = build(:user_extension_config, user: regular_user)
      expect(subject).to permit(regular_user, new_config)
    end

    it "allows super_admins to create configs for others" do
      new_config = build(:user_extension_config, user: other_user)
      expect(subject).to permit(super_admin_user, new_config)
      expect(subject).to permit(owner_user, new_config)
    end

    it "denies regular admins from creating configs for others" do
      new_config = build(:user_extension_config, user: other_user)
      expect(subject).not_to permit(admin_user, new_config)
    end
  end

  permissions :update? do
    it "allows users to update their own config" do
      expect(subject).to permit(regular_user, owned_config)
    end

    it "allows super_admins to update any config" do
      expect(subject).to permit(super_admin_user, other_config)
      expect(subject).to permit(owner_user, other_config)
    end

    it "denies regular admins from updating other users' configs" do
      expect(subject).not_to permit(admin_user, other_config)
    end

    it "denies regular users from updating other users' configs" do
      expect(subject).not_to permit(regular_user, other_config)
    end
  end

  permissions :destroy? do
    it "allows users to delete their own config" do
      expect(subject).to permit(regular_user, owned_config)
    end

    it "allows super_admins to delete non-owner configs" do
      expect(subject).to permit(super_admin_user, other_config)
    end

    it "allows owners to delete any config including owner-owned" do
      expect(subject).to permit(owner_user, owner_config)
    end

    it "denies super_admins from deleting owner-owned configs" do
      expect(subject).not_to permit(super_admin_user, owner_config)
    end

    it "denies regular admins from deleting any configs" do
      expect(subject).not_to permit(admin_user, other_config)
    end

    it "denies regular users from deleting other users' configs" do
      expect(subject).not_to permit(regular_user, other_config)
    end
  end

  describe "Scope" do
    let!(:own_config) { create(:user_extension_config, user: regular_user) }
    let!(:others_config) { create(:user_extension_config, user: other_user) }

    it "returns only the user's own config for regular users" do
      scope = described_class::Scope.new(regular_user, UserExtensionConfig).resolve
      expect(scope).to include(own_config)
      expect(scope).not_to include(others_config)
    end

    it "returns all configs for admins" do
      scope = described_class::Scope.new(admin_user, UserExtensionConfig).resolve
      expect(scope).to include(own_config, others_config)
    end
  end
end
