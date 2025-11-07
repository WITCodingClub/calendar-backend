# frozen_string_literal: true

# Shared examples for Pundit policy tests

RSpec.shared_examples "user-owned resource policy" do |factory_name|
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:other_user) { create(:user, access_level: :user) }
  let(:owner_target) { create(:user, access_level: :owner) }

  let(:owned_resource) { create(factory_name, user: regular_user) }
  let(:other_resource) { create(factory_name, user: other_user) }
  let(:owner_owned_resource) { create(factory_name, user: owner_target) }

  permissions :index? do
    it "allows admins to list all resources" do
      expect(subject).to permit(admin_user, owned_resource)
      expect(subject).to permit(super_admin_user, owned_resource)
      expect(subject).to permit(owner_user, owned_resource)
    end

    it "denies regular users from listing all resources" do
      expect(subject).not_to permit(regular_user, owned_resource)
    end
  end

  permissions :show? do
    it "allows users to view their own resources" do
      expect(subject).to permit(regular_user, owned_resource)
    end

    it "allows admins to view all resources for support" do
      expect(subject).to permit(admin_user, other_resource)
      expect(subject).to permit(super_admin_user, other_resource)
      expect(subject).to permit(owner_user, other_resource)
    end

    it "denies users from viewing other users' resources" do
      expect(subject).not_to permit(regular_user, other_resource)
    end
  end

  permissions :create? do
    it "allows users to create their own resources" do
      new_resource = build(factory_name, user: regular_user)
      expect(subject).to permit(regular_user, new_resource)
    end

    it "allows super_admins to create resources for others" do
      new_resource = build(factory_name, user: other_user)
      expect(subject).to permit(super_admin_user, new_resource)
      expect(subject).to permit(owner_user, new_resource)
    end

    it "denies regular admins from creating resources for others" do
      new_resource = build(factory_name, user: other_user)
      expect(subject).not_to permit(admin_user, new_resource)
    end
  end

  permissions :update? do
    it "allows users to update their own resources" do
      expect(subject).to permit(regular_user, owned_resource)
    end

    it "allows super_admins to update any resources" do
      expect(subject).to permit(super_admin_user, other_resource)
      expect(subject).to permit(owner_user, other_resource)
    end

    it "denies regular admins from updating other users' resources" do
      expect(subject).not_to permit(admin_user, other_resource)
    end

    it "denies regular users from updating other users' resources" do
      expect(subject).not_to permit(regular_user, other_resource)
    end
  end

  permissions :destroy? do
    it "allows users to delete their own resources" do
      expect(subject).to permit(regular_user, owned_resource)
    end

    it "allows super_admins to delete non-owner resources" do
      expect(subject).to permit(super_admin_user, other_resource)
    end

    it "allows owners to delete any resources including owner-owned" do
      expect(subject).to permit(owner_user, owner_owned_resource)
    end

    it "denies super_admins from deleting owner-owned resources" do
      expect(subject).not_to permit(super_admin_user, owner_owned_resource)
    end

    it "denies regular admins from deleting any resources" do
      expect(subject).not_to permit(admin_user, other_resource)
    end

    it "denies regular users from deleting other users' resources" do
      expect(subject).not_to permit(regular_user, other_resource)
    end
  end
end

RSpec.shared_examples "public-read resource policy" do |factory_name|
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:resource) { create(factory_name) }

  permissions :index?, :show? do
    it "allows everyone to view resources" do
      expect(subject).to permit(regular_user, resource)
      expect(subject).to permit(admin_user, resource)
      expect(subject).to permit(super_admin_user, resource)
      expect(subject).to permit(owner_user, resource)
    end

    it "allows unauthenticated access" do
      expect(subject).to permit(nil, resource)
    end
  end

  permissions :create?, :update? do
    it "allows admins to manage resources" do
      expect(subject).to permit(admin_user, resource)
      expect(subject).to permit(super_admin_user, resource)
      expect(subject).to permit(owner_user, resource)
    end

    it "denies regular users from managing resources" do
      expect(subject).not_to permit(regular_user, resource)
    end

    it "denies unauthenticated users from managing resources" do
      expect(subject).not_to permit(nil, resource)
    end
  end

  permissions :destroy? do
    it "allows only super_admins to delete resources" do
      expect(subject).to permit(super_admin_user, resource)
      expect(subject).to permit(owner_user, resource)
    end

    it "denies regular admins from deleting resources" do
      expect(subject).not_to permit(admin_user, resource)
    end

    it "denies regular users from deleting resources" do
      expect(subject).not_to permit(regular_user, resource)
    end
  end
end

RSpec.shared_examples "admin-only resource policy" do |factory_name|
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:resource) { create(factory_name) }

  permissions :index?, :show? do
    it "allows admins to view resources" do
      expect(subject).to permit(admin_user, resource)
      expect(subject).to permit(super_admin_user, resource)
      expect(subject).to permit(owner_user, resource)
    end

    it "denies regular users from viewing resources" do
      expect(subject).not_to permit(regular_user, resource)
    end
  end

  permissions :create?, :update? do
    it "denies everyone from creating or updating (system-generated)" do
      expect(subject).not_to permit(admin_user, resource)
      expect(subject).not_to permit(super_admin_user, resource)
      expect(subject).not_to permit(owner_user, resource)
      expect(subject).not_to permit(regular_user, resource)
    end
  end

  permissions :destroy? do
    it "allows only super_admins to delete resources" do
      expect(subject).to permit(super_admin_user, resource)
      expect(subject).to permit(owner_user, resource)
    end

    it "denies regular admins from deleting resources" do
      expect(subject).not_to permit(admin_user, resource)
    end

    it "denies regular users from deleting resources" do
      expect(subject).not_to permit(regular_user, resource)
    end
  end
end
