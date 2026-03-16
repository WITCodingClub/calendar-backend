# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  notifications_disabled_until :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#
require "rails_helper"

RSpec.describe User do
  describe "associations" do
    let(:user) { create(:user) }

    it "has many emails" do
      expect(user).to respond_to(:emails)
    end

    it "has many oauth_credentials" do
      expect(user).to respond_to(:oauth_credentials)
    end

    it "has many enrollments" do
      expect(user).to respond_to(:enrollments)
    end

    it "has many calendar_preferences" do
      expect(user).to respond_to(:calendar_preferences)
    end
  end

  describe "access levels" do
    it "defaults to user access level" do
      user = create(:user)
      expect(user.access_level).to eq("user")
    end

    it "supports admin access level" do
      user = create(:user, access_level: :admin)
      expect(user).to be_admin
    end

    it "supports super_admin access level" do
      user = create(:user, access_level: :super_admin)
      expect(user).to be_super_admin
    end

    it "supports owner access level" do
      user = create(:user, access_level: :owner)
      expect(user).to be_owner
    end

    describe "#admin_access?" do
      it "returns false for regular users" do
        expect(create(:user, access_level: :user).admin_access?).to be false
      end

      it "returns true for admins" do
        expect(create(:user, access_level: :admin).admin_access?).to be true
      end

      it "returns true for super_admins" do
        expect(create(:user, access_level: :super_admin).admin_access?).to be true
      end

      it "returns true for owners" do
        expect(create(:user, access_level: :owner).admin_access?).to be true
      end
    end
  end

  describe ".find_by_email" do
    it "returns the user associated with the given email" do
      user = create(:user)
      email = create(:email, user: user, primary: true)

      expect(described_class.find_by_email(email.email)).to eq(user)
    end

    it "returns nil when no user has that email" do
      expect(described_class.find_by_email("nobody@example.com")).to be_nil
    end
  end

  describe ".find_or_create_by_email" do
    context "when a user with that email already exists" do
      it "returns the existing user" do
        user = create(:user)
        email = create(:email, user: user, primary: true)

        result = described_class.find_or_create_by_email(email.email, "New", "Name")

        expect(result).to eq(user)
      end
    end

    context "when no user has that email" do
      it "creates and returns a new user" do
        expect {
          described_class.find_or_create_by_email("newuser@example.com", "Jane", "Doe")
        }.to change(described_class, :count).by(1)
      end

      it "sets first_name and last_name on the new user" do
        user = described_class.find_or_create_by_email("newuser2@example.com", "Jane", "Doe")
        expect(user.first_name).to eq("Jane")
        expect(user.last_name).to eq("Doe")
      end

      it "creates a primary email record for the new user" do
        user = described_class.find_or_create_by_email("newuser3@example.com", "Jane", "Doe")
        expect(user.emails.find_by(primary: true)&.email).to eq("newuser3@example.com")
      end
    end
  end

  describe "#full_name" do
    it "returns the combined first and last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.full_name).to eq("John Doe")
    end
  end

  describe "#email" do
    it "returns the primary email address" do
      user = create(:user)
      primary = create(:email, user: user, primary: true)
      expect(user.email).to eq(primary.email)
    end
  end

  describe "scopes" do
    let!(:regular_user) { create(:user, access_level: :user) }
    let!(:admin_user) { create(:user, access_level: :admin) }
    let!(:super_admin_user) { create(:user, access_level: :super_admin) }
    let!(:owner_user) { create(:user, access_level: :owner) }

    describe ".admins" do
      it "includes admins, super_admins, and owners" do
        expect(described_class.admins.to_a).to include(admin_user, super_admin_user, owner_user)
      end

      it "excludes regular users" do
        expect(described_class.admins).not_to include(regular_user)
      end
    end

    describe ".owners" do
      it "includes only owner-level users" do
        expect(described_class.owners).to include(owner_user)
        expect(described_class.owners).not_to include(admin_user, super_admin_user, regular_user)
      end
    end
  end

  describe "DND (Do Not Disturb) mode" do
    let(:user) { create(:user) }

    describe "#notifications_disabled?" do
      it "returns false when notifications_disabled_until is nil" do
        user.notifications_disabled_until = nil
        expect(user.notifications_disabled?).to be false
      end

      it "returns false when notifications_disabled_until is in the past" do
        user.notifications_disabled_until = 1.hour.ago
        expect(user.notifications_disabled?).to be false
      end

      it "returns true when notifications_disabled_until is in the future" do
        user.notifications_disabled_until = 1.hour.from_now
        expect(user.notifications_disabled?).to be true
      end
    end

    describe "#disable_notifications!" do
      it "sets notifications_disabled_until to a far future date when called without duration" do
        user.disable_notifications!

        expect(user.notifications_disabled_until).to be > 50.years.from_now
        expect(user.notifications_disabled?).to be true
      end

      it "sets notifications_disabled_until to the specified duration from now" do
        freeze_time do
          user.disable_notifications!(duration: 2.hours)

          expect(user.notifications_disabled_until).to be_within(1.second).of(2.hours.from_now)
          expect(user.notifications_disabled?).to be true
        end
      end
    end

    describe "#enable_notifications!" do
      it "clears notifications_disabled_until" do
        user.disable_notifications!
        expect(user.notifications_disabled?).to be true

        user.enable_notifications!

        expect(user.notifications_disabled_until).to be_nil
        expect(user.notifications_disabled?).to be false
      end
    end
  end
end
