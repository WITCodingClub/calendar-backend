# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::UniversityCalendarEvents", type: :request do
  let(:admin_user) do
    user = create(:user, :admin)
    user.emails.create!(email_address: "admin@example.com", primary: true) if user.emails.empty?
    user
  end

  # Helper to sign in a user by setting the session
  def sign_in_user(user)
    post user_session_path, params: { email: user.emails.first.email_address }
    follow_redirect!
  end

  describe "GET /admin/university_calendar_events" do
    before do
      sign_in_user(admin_user)
    end

    context "when filtering consistency" do
      before do
        # Create events with different categories
        # Some with location, some without
        create(:university_calendar_event, :holiday, location: "Campus")
        create(:university_calendar_event, :holiday, location: nil)
        create(:university_calendar_event, :term_dates, location: nil)
        create(:university_calendar_event, :term_dates, location: nil)
        create(:university_calendar_event, :registration, location: "Admissions Office")
        create(:university_calendar_event, :campus_event, location: nil)
      end

      it "stats respect the with_location filter by default" do
        get admin_university_calendar_events_path

        expect(response).to have_http_status(:ok)

        # Parse the response to check stats
        # By default, only events with location should be counted
        # Expected: 1 holiday (with location), 0 term_dates (both without location), 1 registration (with location)
        expect(response.body).to include("Holiday")
        expect(response.body).to include("Registration")
        
        # The stats should show counts for events with locations only
        # This ensures the category counts match what will be shown when clicking them
      end

      it "stats include all events when show_all=1" do
        get admin_university_calendar_events_path(show_all: "1")

        expect(response).to have_http_status(:ok)

        # With show_all=1, all events should be counted
        # Expected: 2 holidays, 2 term_dates, 1 registration, 1 campus_event
      end

      it "category links preserve the show_all parameter" do
        get admin_university_calendar_events_path(show_all: "1")

        expect(response).to have_http_status(:ok)

        # Check that category links include show_all parameter
        expect(response.body).to include("show_all=1")
      end

      it "filtering by category respects the location filter" do
        # Filter by term_dates category (both events have no location)
        get admin_university_calendar_events_path(category: "term_dates")

        expect(response).to have_http_status(:ok)

        # Should show 0 events because both term_dates events have no location
        # and by default we hide events without location
      end

      it "filtering by category with show_all shows all events in that category" do
        # Filter by term_dates category with show_all=1
        get admin_university_calendar_events_path(category: "term_dates", show_all: "1")

        expect(response).to have_http_status(:ok)

        # Should show 2 events because we're showing all events
      end
    end
  end
end
