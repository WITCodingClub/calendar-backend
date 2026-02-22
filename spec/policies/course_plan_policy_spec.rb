# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePlanPolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:other_user) { create(:user, access_level: :user) }

  let(:term) { create(:term) }
  let(:owned_plan) { create(:course_plan, user: regular_user, term: term) }
  let(:other_plan) { create(:course_plan, user: other_user, term: term) }

  permissions :show? do
    it "allows users to view their own plans" do
      expect(subject).to permit(regular_user, owned_plan)
    end

    it "allows admins to view any plan" do
      expect(subject).to permit(admin_user, other_plan)
      expect(subject).to permit(super_admin_user, other_plan)
      expect(subject).to permit(owner_user, other_plan)
    end

    it "denies regular users from viewing others' plans" do
      expect(subject).not_to permit(regular_user, other_plan)
    end
  end

  permissions :create? do
    it "allows any authenticated user to create a plan" do
      new_plan = build(:course_plan, user: regular_user, term: term)
      expect(subject).to permit(regular_user, new_plan)
      expect(subject).to permit(admin_user, new_plan)
      expect(subject).to permit(super_admin_user, new_plan)
    end
  end

  permissions :update? do
    it "allows users to update their own plans" do
      expect(subject).to permit(regular_user, owned_plan)
    end

    it "allows admins to update any plan" do
      expect(subject).to permit(admin_user, other_plan)
      expect(subject).to permit(super_admin_user, other_plan)
    end

    it "denies regular users from updating others' plans" do
      expect(subject).not_to permit(regular_user, other_plan)
    end
  end

  permissions :destroy? do
    it "allows users to delete their own plans" do
      expect(subject).to permit(regular_user, owned_plan)
    end

    it "allows super_admins to delete non-owner plans" do
      expect(subject).to permit(super_admin_user, other_plan)
    end

    it "denies regular admins from deleting plans" do
      expect(subject).not_to permit(admin_user, other_plan)
    end

    it "denies regular users from deleting others' plans" do
      expect(subject).not_to permit(regular_user, other_plan)
    end
  end

  describe CoursePlanPolicy::Scope do
    it "returns all plans for admins" do
      owned_plan
      other_plan
      scope = described_class::Scope.new(admin_user, CoursePlan).resolve
      expect(scope).to include(owned_plan, other_plan)
    end

    it "returns only own plans for regular users" do
      owned_plan
      other_plan
      scope = described_class::Scope.new(regular_user, CoursePlan).resolve
      expect(scope).to include(owned_plan)
      expect(scope).not_to include(other_plan)
    end
  end
end
