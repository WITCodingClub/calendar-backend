# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCatalogPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }

  # Course catalog is a headless policy (no record)
  # We pass :course_catalog as a symbol
  let(:record) { :course_catalog }

  permissions :index? do
    it "allows admins to view the page" do
      expect(subject).to permit(admin_user, record)
      expect(subject).to permit(super_admin_user, record)
      expect(subject).to permit(owner_user, record)
    end

    it "denies regular users from viewing the page" do
      expect(subject).not_to permit(regular_user, record)
    end

    it "denies unauthenticated users from viewing the page" do
      expect(subject).not_to permit(nil, record)
    end
  end

  permissions :fetch? do
    it "allows admins to fetch the course catalog" do
      expect(subject).to permit(admin_user, record)
      expect(subject).to permit(super_admin_user, record)
      expect(subject).to permit(owner_user, record)
    end

    it "denies regular users from fetching the course catalog" do
      expect(subject).not_to permit(regular_user, record)
    end

    it "denies unauthenticated users from fetching the course catalog" do
      expect(subject).not_to permit(nil, record)
    end
  end

  permissions :process? do
    it "allows super_admin and above to process courses" do
      expect(subject).to permit(super_admin_user, record)
      expect(subject).to permit(owner_user, record)
    end

    it "denies admins from processing courses" do
      expect(subject).not_to permit(admin_user, record)
    end

    it "denies regular users from processing courses" do
      expect(subject).not_to permit(regular_user, record)
    end

    it "denies unauthenticated users from processing courses" do
      expect(subject).not_to permit(nil, record)
    end
  end
end
