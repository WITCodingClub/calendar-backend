# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarEventPolicy, type: :policy do
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

  let(:owned_event) { create(:google_calendar_event, google_calendar: owned_calendar) }
  let(:other_event) { create(:google_calendar_event, google_calendar: other_calendar) }
  let(:owner_event) { create(:google_calendar_event, google_calendar: owner_calendar) }

  permissions :index? do
    it "allows admins to list all events" do
      expect(subject).to permit(admin_user, owned_event)
      expect(subject).to permit(super_admin_user, owned_event)
      expect(subject).to permit(owner_user, owned_event)
    end

    it "denies regular users" do
      expect(subject).not_to permit(regular_user, owned_event)
    end
  end

  permissions :show? do
    it "allows the event owner to view their own events" do
      expect(subject).to permit(regular_user, owned_event)
    end

    it "allows admins to view any event" do
      expect(subject).to permit(admin_user, other_event)
      expect(subject).to permit(super_admin_user, other_event)
      expect(subject).to permit(owner_user, other_event)
    end

    it "denies regular users from viewing other users' events" do
      expect(subject).not_to permit(regular_user, other_event)
    end
  end

  permissions :create? do
    it "allows the event owner to create events on their calendar" do
      expect(subject).to permit(regular_user, owned_event)
    end

    it "allows super_admins and owners to create any event" do
      expect(subject).to permit(super_admin_user, other_event)
      expect(subject).to permit(owner_user, other_event)
    end

    it "denies regular admins from creating events on other users' calendars" do
      expect(subject).not_to permit(admin_user, other_event)
    end

    it "denies regular users from creating events on other calendars" do
      expect(subject).not_to permit(regular_user, other_event)
    end
  end

  permissions :update? do
    it "allows the event owner to update their own events" do
      expect(subject).to permit(regular_user, owned_event)
    end

    it "allows super_admins and owners to update any event" do
      expect(subject).to permit(super_admin_user, other_event)
      expect(subject).to permit(owner_user, other_event)
    end

    it "denies regular admins from updating events on other users' calendars" do
      expect(subject).not_to permit(admin_user, other_event)
    end

    it "denies regular users from updating events on other calendars" do
      expect(subject).not_to permit(regular_user, other_event)
    end
  end

  permissions :destroy? do
    it "allows the event owner to destroy their own events" do
      expect(subject).to permit(regular_user, owned_event)
    end

    it "allows super_admins to destroy non-owner events" do
      expect(subject).to permit(super_admin_user, other_event)
    end

    it "allows owner users to destroy any event including owner-owned" do
      expect(subject).to permit(owner_user, owner_event)
    end

    it "denies super_admins from destroying owner-owned events" do
      expect(subject).not_to permit(super_admin_user, owner_event)
    end

    it "denies regular admins from destroying events" do
      expect(subject).not_to permit(admin_user, other_event)
    end

    it "denies regular users from destroying other users' events" do
      expect(subject).not_to permit(regular_user, other_event)
    end
  end

  describe "Scope" do
    let!(:owned_cal_event) { create(:google_calendar_event, google_calendar: owned_calendar) }
    let!(:other_cal_event) { create(:google_calendar_event, google_calendar: other_calendar) }

    it "returns only the user's own events for regular users" do
      scope = described_class::Scope.new(regular_user, GoogleCalendarEvent).resolve
      expect(scope).to include(owned_cal_event)
      expect(scope).not_to include(other_cal_event)
    end

    it "returns all events for admins" do
      scope = described_class::Scope.new(admin_user, GoogleCalendarEvent).resolve
      expect(scope).to include(owned_cal_event, other_cal_event)
    end
  end
end
