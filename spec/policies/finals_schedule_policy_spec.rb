# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedulePolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:finals_schedule) { create(:finals_schedule) }

  permissions :index?, :show? do
    it "allows admins to view finals schedules" do
      expect(subject).to permit(admin_user, finals_schedule)
      expect(subject).to permit(super_admin_user, finals_schedule)
      expect(subject).to permit(owner_user, finals_schedule)
    end

    it "denies regular users from viewing finals schedules" do
      expect(subject).not_to permit(regular_user, finals_schedule)
    end

    it "denies unauthenticated users" do
      expect(subject).not_to permit(nil, finals_schedule)
    end
  end

  permissions :new?, :create? do
    it "allows super_admins to upload finals schedules" do
      expect(subject).to permit(super_admin_user, finals_schedule)
      expect(subject).to permit(owner_user, finals_schedule)
    end

    it "denies regular admins from uploading finals schedules" do
      expect(subject).not_to permit(admin_user, finals_schedule)
    end

    it "denies regular users from uploading finals schedules" do
      expect(subject).not_to permit(regular_user, finals_schedule)
    end
  end

  permissions :destroy? do
    it "allows super_admins to delete finals schedules" do
      expect(subject).to permit(super_admin_user, finals_schedule)
      expect(subject).to permit(owner_user, finals_schedule)
    end

    it "denies regular admins from deleting finals schedules" do
      expect(subject).not_to permit(admin_user, finals_schedule)
    end

    it "denies regular users from deleting finals schedules" do
      expect(subject).not_to permit(regular_user, finals_schedule)
    end
  end

  describe "Scope" do
    let!(:schedule1) { create(:finals_schedule) }
    let!(:schedule2) { create(:finals_schedule) }

    it "returns all schedules for admin users" do
      scope = described_class::Scope.new(admin_user, FinalsSchedule.all).resolve
      expect(scope).to include(schedule1, schedule2)
    end

    it "returns all schedules for super_admin users" do
      scope = described_class::Scope.new(super_admin_user, FinalsSchedule.all).resolve
      expect(scope).to include(schedule1, schedule2)
    end

    it "returns no schedules for regular users" do
      scope = described_class::Scope.new(regular_user, FinalsSchedule.all).resolve
      expect(scope).to be_empty
    end

    it "returns no schedules for unauthenticated users" do
      scope = described_class::Scope.new(nil, FinalsSchedule.all).resolve
      expect(scope).to be_empty
    end
  end
end
