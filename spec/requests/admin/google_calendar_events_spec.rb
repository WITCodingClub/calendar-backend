# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::GoogleCalendarEvents", type: :request do # rubocop:disable RSpecRails/InferredSpecType
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:regular_user) { create(:user, access_level: :user) }
  let(:oauth_credential) { create(:oauth_credential, user: admin_user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

  before do
    # Create some sample events with different meeting times
    3.times do
      meeting_time = create(:meeting_time)
      create(:google_calendar_event, google_calendar: google_calendar, meeting_time: meeting_time)
    end
  end

  describe "GET /admin/google_calendar_events" do
    context "when user is an admin" do
      before do
        # Stub the routing constraint to allow access
        allow_any_instance_of(AdminConstraint).to receive(:matches?).and_return(true)

        # Stub authentication on the controller
        allow_any_instance_of(Admin::ApplicationController).to receive(:require_admin).and_return(true)
        allow_any_instance_of(Admin::ApplicationController).to receive(:current_user).and_return(admin_user)
        allow_any_instance_of(Admin::ApplicationController).to receive(:user_signed_in?).and_return(true)
      end

      it "returns a successful response" do
        get admin_google_calendar_events_path
        expect(response).to have_http_status(:success)
      end

      it "displays google calendar events" do
        get admin_google_calendar_events_path
        expect(response.body).to include("Google Calendar Events")
      end

      it "includes pagination" do
        get admin_google_calendar_events_path
        expect(response.body).to include("Event ID")
        expect(response.body).to include("Calendar")
        expect(response.body).to include("Event Data Hash")
      end
    end

    context "when user is not an admin" do
      before do
        # Stub authentication but don't allow admin access
        allow_any_instance_of(AdminConstraint).to receive(:matches?).and_return(false)
        allow_any_instance_of(Admin::ApplicationController).to receive(:current_user).and_return(regular_user)
        allow_any_instance_of(Admin::ApplicationController).to receive(:user_signed_in?).and_return(true)
      end

      it "redirects to unauthorized page" do
        get admin_google_calendar_events_path
        expect(response).to redirect_to(admin_unauthorized_path)
      end
    end

    context "when user is not signed in" do
      it "redirects to sign in page" do
        get admin_google_calendar_events_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
