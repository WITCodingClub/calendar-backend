# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }

  permissions :show?, :index? do
    it "allows admins, super_admins, and owners" do
      expect(subject).to permit(admin_user, :dashboard)
      expect(subject).to permit(super_admin_user, :dashboard)
      expect(subject).to permit(owner_user, :dashboard)
    end

    it "denies regular users" do
      expect(subject).not_to permit(regular_user, :dashboard)
    end

    it "denies unauthenticated users" do
      expect(subject).not_to permit(nil, :dashboard)
    end
  end
end
