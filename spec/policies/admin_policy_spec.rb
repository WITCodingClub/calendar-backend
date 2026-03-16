# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }

  permissions :blazer? do
    it "allows admins, super_admins, and owners" do
      expect(subject).to permit(admin_user, :admin)
      expect(subject).to permit(super_admin_user, :admin)
      expect(subject).to permit(owner_user, :admin)
    end

    it "denies regular users" do
      expect(subject).not_to permit(regular_user, :admin)
    end

    it "denies unauthenticated users" do
      expect(subject).not_to permit(nil, :admin)
    end
  end

  permissions :flipper? do
    it "allows super_admins and owners" do
      expect(subject).to permit(super_admin_user, :admin)
      expect(subject).to permit(owner_user, :admin)
    end

    it "denies regular admins" do
      expect(subject).not_to permit(admin_user, :admin)
    end

    it "denies regular users" do
      expect(subject).not_to permit(regular_user, :admin)
    end

    it "denies unauthenticated users" do
      expect(subject).not_to permit(nil, :admin)
    end
  end

  permissions :access_admin_endpoints? do
    it "allows admins, super_admins, and owners" do
      expect(subject).to permit(admin_user, :admin)
      expect(subject).to permit(super_admin_user, :admin)
      expect(subject).to permit(owner_user, :admin)
    end

    it "denies regular users" do
      expect(subject).not_to permit(regular_user, :admin)
    end

    it "denies unauthenticated users" do
      expect(subject).not_to permit(nil, :admin)
    end
  end
end
