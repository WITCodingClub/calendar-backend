# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarPolicy, type: :policy do
  # Note: GoogleCalendar ownership is through oauth_credential, not directly through user_id
  # So we need custom specs instead of the shared examples

  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:other_user) { create(:user, access_level: :user) }
  let(:owner_target) { create(:user, access_level: :owner) }

  let(:owned_credential) { create(:oauth_credential, user: regular_user) }
  let(:other_credential) { create(:oauth_credential, user: other_user) }
  let(:owner_credential) { create(:oauth_credential, user: owner_target) }

  let(:owned_calendar) { create(:google_calendar, oauth_credential: owned_credential) }
  let(:other_calendar) { create(:google_calendar, oauth_credential: other_credential) }
  let(:owner_calendar) { create(:google_calendar, oauth_credential: owner_credential) }

  permissions :index? do
    it "allows admins to list all calendars" do
      expect(subject).to permit(admin_user, GoogleCalendar)
      expect(subject).to permit(super_admin_user, GoogleCalendar)
      expect(subject).to permit(owner_user, GoogleCalendar)
    end
  end

  permissions :show? do
    it "allows users to view their own calendars" do
      expect(subject).to permit(regular_user, owned_calendar)
    end

    it "allows admins to view all calendars" do
      expect(subject).to permit(admin_user, other_calendar)
    end

    it "denies users from viewing other users' calendars" do
      expect(subject).not_to permit(regular_user, other_calendar)
    end
  end

  permissions :destroy? do
    it "allows users to delete their own calendars" do
      expect(subject).to permit(regular_user, owned_calendar)
    end

    it "allows super_admins to delete non-owner calendars" do
      expect(subject).to permit(super_admin_user, other_calendar)
    end

    it "denies super_admins from deleting owner calendars" do
      expect(subject).not_to permit(super_admin_user, owner_calendar)
    end
  end
end
