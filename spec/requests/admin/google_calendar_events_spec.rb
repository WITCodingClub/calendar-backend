# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::GoogleCalendarEvents" do
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:regular_user) { create(:user, access_level: :user) }
  let(:oauth_credential) { create(:oauth_credential, user: admin_user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

  before do
    # Create some sample events
    meeting_time = create(:meeting_time)
    create_list(:google_calendar_event, 3, google_calendar: google_calendar, meeting_time: meeting_time)
  end

  describe "GET /admin/google_calendar_events" do
    context "when user is an admin" do
      before { sign_in admin_user }

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
      before { sign_in regular_user }

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
